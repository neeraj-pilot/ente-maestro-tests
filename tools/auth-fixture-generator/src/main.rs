use std::{
    env, fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, bail, ensure};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, AuthenticatedAccount,
    CreateAccountParams, LoginParams, OtpPurpose, SecondFactorMethod, SetupTwoFactorParams,
    TotpPurpose,
};
use ente_core::crypto::{
    Header, Key, Nonce, SecretVec, blob, decode_b64, encode_b64, encode_b64_url_safe, secretbox,
};
use hmac::{Hmac, Mac};
use reqwest::{Client, Method, Response};
use serde::{Deserialize, Serialize};
use sha1::Sha1;
use url::Url;
use zeroize::Zeroizing;

const ENDPOINT: &str = "http://127.0.0.1:8080";
const EMAIL_OTP: &str = "123456";
const CLIENT_PACKAGE: &str = "io.ente.auth";
const NOTICE: &str = "Public local test fixtures. Never use these identities or credentials outside ephemeral local Museum instances.";

const BASIC_EMAIL: &str = "auth-maestro-fixture-basic-v2@example.org";
const BASIC_PASSWORD: &str = "EnteAuth-MaestroFixture-Basic-v2!";
const TOTP_EMAIL: &str = "auth-maestro-fixture-totp-v2@example.org";
const TOTP_PASSWORD: &str = "EnteAuth-MaestroFixture-Totp-v2!";
const RECOVERY_EMAIL: &str = "auth-maestro-fixture-recovery-v2@example.org";
const RECOVERY_PASSWORD: &str = "EnteAuth-MaestroFixture-Recovery-v2!";
const RECOVERED_PASSWORD: &str = "EnteAuth-MaestroFixture-Recovered-v2!";

type HmacSha1 = Hmac<Sha1>;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FixtureCredentials {
    classification: &'static str,
    notice: &'static str,
    fixture_version: u8,
    allowed_endpoint: &'static str,
    accounts: FixtureAccounts,
}

#[derive(Serialize)]
struct FixtureAccounts {
    basic: FixtureAccount,
    totp: FixtureAccount,
    recovery: FixtureAccount,
}

#[derive(Deserialize)]
struct VerificationCredentials {
    accounts: VerificationAccounts,
}

#[derive(Deserialize)]
struct VerificationAccounts {
    basic: VerificationAccount,
    totp: VerificationAccount,
    recovery: VerificationAccount,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct VerificationAccount {
    email: String,
    password: String,
    totp_secret: Option<String>,
    codes: Vec<FixtureCode>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FixtureAccount {
    role: &'static str,
    user_id: i64,
    email: &'static str,
    password: &'static str,
    recovery_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    totp_secret: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    recovered_password: Option<&'static str>,
    capabilities: Vec<&'static str>,
    codes: Vec<FixtureCode>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
struct FixtureCode {
    id: String,
    issuer: String,
    account: String,
    secret: String,
    tags: Vec<String>,
    note: String,
    pinned: bool,
    trashed: bool,
    position: i32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CodeDisplay<'a> {
    pinned: bool,
    trashed: bool,
    last_used_at: i64,
    tap_count: i64,
    tags: &'a [String],
    note: &'a str,
    position: i32,
    icon_src: &'static str,
    icon_id: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateKeyRequest {
    encrypted_key: String,
    header: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AuthKeyResponse {
    encrypted_key: String,
    header: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateEntityRequest {
    encrypted_data: String,
    header: String,
}

#[derive(Deserialize)]
struct EntityDiffResponse {
    diff: Vec<AuthEntityResponse>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AuthEntityResponse {
    encrypted_data: Option<String>,
    header: Option<String>,
    is_deleted: bool,
}

struct FixtureUi {
    totp_secret: Option<String>,
}

impl FixtureUi {
    fn new() -> Self {
        Self { totp_secret: None }
    }

    fn with_totp(secret: String) -> Self {
        Self {
            totp_secret: Some(secret),
        }
    }
}

impl AuthFlowUi for FixtureUi {
    fn read_email_otp(
        &mut self,
        _email: &str,
        _purpose: OtpPurpose,
        _resent: bool,
    ) -> ente_accounts::Result<String> {
        Ok(EMAIL_OTP.to_owned())
    }

    fn read_totp_code(&mut self, _purpose: TotpPurpose) -> ente_accounts::Result<String> {
        let secret = self.totp_secret.as_deref().ok_or_else(|| {
            ente_accounts::Error::InvalidInput("TOTP setup secret was not presented".into())
        })?;
        Ok(current_totp(secret))
    }

    fn report_retryable_error(&mut self, message: &str) -> ente_accounts::Result<()> {
        eprintln!("Retrying fixture setup after server response: {message}");
        Ok(())
    }

    fn choose_second_factor(
        &mut self,
        methods: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        if !methods.contains(&SecondFactorMethod::Totp) {
            return Err(ente_accounts::Error::InvalidInput(
                "TOTP is not available for the fixture account".into(),
            ));
        }
        Ok(SecondFactorMethod::Totp)
    }

    fn present_passkey_verification(&mut self, _url: &str) -> ente_accounts::Result<()> {
        Err(ente_accounts::Error::InvalidInput(
            "Passkeys are outside the Auth fixture contract".into(),
        ))
    }

    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        Err(ente_accounts::Error::InvalidInput(
            "Passkeys are outside the Auth fixture contract".into(),
        ))
    }

    fn present_totp_secret(
        &mut self,
        secret_code: &str,
        _qr_code: &str,
    ) -> ente_accounts::Result<()> {
        self.totp_secret = Some(secret_code.to_owned());
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let endpoint = env::var("AUTH_FIXTURE_ENDPOINT").unwrap_or_else(|_| ENDPOINT.to_owned());
    ensure!(
        endpoint == ENDPOINT,
        "fixture generation is restricted to {ENDPOINT}; got {endpoint}"
    );

    let mut arguments = env::args().skip(1);
    let command = arguments
        .next()
        .context("expected generate or verify command")?;
    let path = arguments.next().map(PathBuf::from).with_context(|| {
        format!("{command} requires a public-test-credentials.json path argument")
    })?;
    ensure!(arguments.next().is_none(), "unexpected extra arguments");

    match command.as_str() {
        "generate" => generate(&endpoint, &path).await,
        "verify" => verify(&endpoint, &path).await,
        _ => bail!("unknown command {command}; expected generate or verify"),
    }
}

async fn generate(endpoint: &str, output: &Path) -> Result<()> {
    let basic = create_fixture_account(
        endpoint,
        "basic",
        BASIC_EMAIL,
        BASIC_PASSWORD,
        false,
        basic_codes(),
    )
    .await?;
    let totp = create_fixture_account(
        endpoint,
        "totp",
        TOTP_EMAIL,
        TOTP_PASSWORD,
        true,
        totp_codes(),
    )
    .await?;
    let mut recovery = create_fixture_account(
        endpoint,
        "recovery",
        RECOVERY_EMAIL,
        RECOVERY_PASSWORD,
        false,
        recovery_codes(),
    )
    .await?;
    recovery.recovered_password = Some(RECOVERED_PASSWORD);

    let credentials = FixtureCredentials {
        classification: "PUBLIC_LOCAL_TEST_FIXTURE",
        notice: NOTICE,
        fixture_version: 2,
        allowed_endpoint: ENDPOINT,
        accounts: FixtureAccounts {
            basic,
            totp,
            recovery,
        },
    };

    write_json_atomically(output, &credentials)?;
    println!("Wrote Auth fixture credentials to {}", output.display());
    Ok(())
}

async fn verify(endpoint: &str, credentials_path: &Path) -> Result<()> {
    let payload = fs::read(credentials_path).context("read fixture credentials")?;
    let credentials: VerificationCredentials =
        serde_json::from_slice(&payload).context("parse fixture credentials")?;

    verify_login(endpoint, credentials.accounts.basic, false).await?;
    verify_login(endpoint, credentials.accounts.totp, true).await?;
    verify_login(endpoint, credentials.accounts.recovery, false).await?;
    println!("Verified fixture credentials and decrypted Auth entities");
    Ok(())
}

async fn verify_login(
    endpoint: &str,
    account: VerificationAccount,
    expect_totp: bool,
) -> Result<()> {
    ensure_fixture_identity(&account.email)?;
    let mut ui = match (expect_totp, account.totp_secret) {
        (true, Some(secret)) => FixtureUi::with_totp(secret),
        (true, None) => bail!("TOTP fixture does not contain a TOTP secret"),
        (false, Some(_)) => bail!("non-TOTP fixture unexpectedly contains a TOTP secret"),
        (false, None) => FixtureUi::new(),
    };
    let client = AccountsClient::new(
        AccountsClientConfig::new(CLIENT_PACKAGE)
            .with_origin(endpoint)
            .with_user_agent("ente-auth-maestro-fixture-verifier/2"),
    )
    .context("create Ente accounts client")?;
    let mut flow = AuthFlow::new(&client, &mut ui);
    let authenticated = flow
        .login(LoginParams {
            email: account.email,
            password: Zeroizing::new(account.password),
        })
        .await
        .context("verify fixture login")?;
    verify_auth_data(endpoint, &authenticated, &account.codes).await
}

async fn create_fixture_account(
    endpoint: &str,
    role: &'static str,
    email: &'static str,
    password: &'static str,
    enable_totp: bool,
    codes: Vec<FixtureCode>,
) -> Result<FixtureAccount> {
    ensure_fixture_identity(email)?;

    let client = AccountsClient::new(
        AccountsClientConfig::new(CLIENT_PACKAGE)
            .with_origin(endpoint)
            .with_user_agent("ente-auth-maestro-fixture-generator/2"),
    )
    .context("create Ente accounts client")?;
    let mut ui = FixtureUi::new();
    let mut flow = AuthFlow::new(&client, &mut ui);
    let account = flow
        .create_account(CreateAccountParams {
            email: email.to_owned(),
            password: Zeroizing::new(password.to_owned()),
            source: Some("authMaestroFixture".into()),
        })
        .await
        .with_context(|| format!("create {role} fixture account"))?;

    seed_auth_data(endpoint, &account, &codes)
        .await
        .with_context(|| format!("seed {role} Auth entities"))?;

    let recovery_key = account
        .recovery_key
        .clone()
        .context("signup did not return a recovery key")?;
    let totp_secret = if enable_totp {
        let result = flow
            .setup_two_factor(SetupTwoFactorParams {
                master_key: SecretVec::new(account.secrets.master_key.clone()),
                key_attributes: Some(account.key_attributes.clone()),
            })
            .await
            .context("enable TOTP for fixture account")?;
        ensure!(
            result.recovery_key == recovery_key,
            "TOTP setup returned a different recovery key"
        );
        Some(result.secret_code)
    } else {
        None
    };

    let capabilities = match role {
        "basic" => vec![
            "passwordLogin",
            "accountSettings",
            "syncedCodes",
            "bulkMutations",
            "trashRestore",
        ],
        "totp" => vec![
            "passwordLogin",
            "totpLogin",
            "accountSettings",
            "syncedCodes",
        ],
        "recovery" => vec![
            "recoveryKeyPasswordReset",
            "passwordLogin",
            "syncedCodes",
            "recoveryPreservesCodes",
        ],
        _ => bail!("unknown fixture role: {role}"),
    };

    Ok(FixtureAccount {
        role,
        user_id: account.user_id,
        email,
        password,
        recovery_key,
        totp_secret,
        recovered_password: None,
        capabilities,
        codes,
    })
}

async fn seed_auth_data(
    endpoint: &str,
    account: &AuthenticatedAccount,
    codes: &[FixtureCode],
) -> Result<()> {
    let api = AuthApi::new(endpoint, account)?;
    let master_key = Key::try_from_slice(&account.secrets.master_key)
        .context("fixture account master key has invalid length")?;
    let auth_key = Key::generate();
    let encrypted_key = secretbox::encrypt(auth_key.as_bytes(), &master_key);

    api.send_json(
        Method::POST,
        "/authenticator/key",
        &CreateKeyRequest {
            encrypted_key: encode_b64(&encrypted_key.encrypted_data),
            header: encode_b64(encrypted_key.nonce.as_bytes()),
        },
        "create Auth data key",
    )
    .await?;

    for code in codes {
        let plaintext = serialize_code(code)?;
        let encrypted = blob::encrypt(plaintext.as_bytes(), &auth_key)
            .with_context(|| format!("encrypt Auth entity {}", code.id))?;
        api.send_json(
            Method::POST,
            "/authenticator/entity",
            &CreateEntityRequest {
                encrypted_data: encode_b64(&encrypted.encrypted_data),
                header: encode_b64(encrypted.decryption_header.as_bytes()),
            },
            &format!("create Auth entity {}", code.id),
        )
        .await?;
    }
    Ok(())
}

async fn verify_auth_data(
    endpoint: &str,
    account: &AuthenticatedAccount,
    expected_codes: &[FixtureCode],
) -> Result<()> {
    let api = AuthApi::new(endpoint, account)?;
    let key_response: AuthKeyResponse = api
        .get_json("/authenticator/key", "fetch Auth data key")
        .await?;
    let master_key = Key::try_from_slice(&account.secrets.master_key)
        .context("fixture account master key has invalid length")?;
    let encrypted_key = decode_b64(&key_response.encrypted_key).context("decode Auth data key")?;
    let nonce = Nonce::try_from_slice(
        &decode_b64(&key_response.header).context("decode Auth data key nonce")?,
    )?;
    let auth_key = Key::try_from_slice(
        &secretbox::decrypt(&encrypted_key, &nonce, &master_key)
            .context("decrypt Auth data key")?,
    )?;

    let diff: EntityDiffResponse = api
        .get_json(
            "/authenticator/entity/diff?sinceTime=0&limit=500",
            "fetch Auth entities",
        )
        .await?;
    let mut actual = Vec::new();
    for entity in diff.diff.into_iter().filter(|entity| !entity.is_deleted) {
        let encrypted_data = entity
            .encrypted_data
            .context("active Auth entity has no encrypted data")?;
        let header = entity.header.context("active Auth entity has no header")?;
        let header = Header::try_from_slice(&decode_b64(&header).context("decode entity header")?)?;
        let plaintext = blob::decrypt(
            &decode_b64(&encrypted_data).context("decode entity data")?,
            &header,
            &auth_key,
        )
        .context("decrypt Auth entity")?;
        actual.push(String::from_utf8(plaintext).context("Auth entity is not UTF-8")?);
    }

    let mut expected = expected_codes
        .iter()
        .map(serialize_code)
        .collect::<Result<Vec<_>>>()?;
    actual.sort();
    expected.sort();
    ensure!(
        actual == expected,
        "decrypted Auth entities differ for fixture user {}",
        account.user_id
    );
    Ok(())
}

struct AuthApi {
    endpoint: String,
    token: String,
    client: Client,
}

impl AuthApi {
    fn new(endpoint: &str, account: &AuthenticatedAccount) -> Result<Self> {
        Ok(Self {
            endpoint: endpoint.trim_end_matches('/').to_owned(),
            token: encode_b64_url_safe(&account.secrets.token),
            client: Client::builder()
                .user_agent("ente-auth-maestro-fixture/2")
                .build()
                .context("create Auth fixture HTTP client")?,
        })
    }

    async fn send_json(
        &self,
        method: Method,
        path: &str,
        body: &impl Serialize,
        action: &str,
    ) -> Result<()> {
        let response = self
            .request(method, path)
            .json(body)
            .send()
            .await
            .with_context(|| action.to_owned())?;
        require_success(response, action).await?;
        Ok(())
    }

    async fn get_json<T: for<'de> Deserialize<'de>>(&self, path: &str, action: &str) -> Result<T> {
        let response = self
            .request(Method::GET, path)
            .send()
            .await
            .with_context(|| action.to_owned())?;
        require_success(response, action)
            .await?
            .json()
            .await
            .with_context(|| format!("decode response while attempting to {action}"))
    }

    fn request(&self, method: Method, path: &str) -> reqwest::RequestBuilder {
        self.client
            .request(method, format!("{}{}", self.endpoint, path))
            .header("X-Auth-Token", &self.token)
            .header("X-Client-Package", CLIENT_PACKAGE)
    }
}

async fn require_success(response: Response, action: &str) -> Result<Response> {
    let status = response.status();
    if status.is_success() {
        return Ok(response);
    }
    let body = response.text().await.unwrap_or_default();
    bail!("failed to {action}: HTTP {status}: {body}")
}

fn serialize_code(code: &FixtureCode) -> Result<String> {
    let mut url = Url::parse("otpauth://totp/fixture").context("create Auth code URL")?;
    url.set_path(&format!("{}:{}", code.issuer, code.account));
    let display = serde_json::to_string(&CodeDisplay {
        pinned: code.pinned,
        trashed: code.trashed,
        last_used_at: 0,
        tap_count: 0,
        tags: &code.tags,
        note: &code.note,
        position: code.position,
        icon_src: "",
        icon_id: "",
    })
    .context("serialize Auth code display data")?;
    url.query_pairs_mut()
        .append_pair("algorithm", "SHA1")
        .append_pair("digits", "6")
        .append_pair("issuer", &code.issuer)
        .append_pair("period", "30")
        .append_pair("secret", &code.secret)
        .append_pair("codeDisplay", &display);
    serde_json::to_string(url.as_str()).context("serialize Auth code entity")
}

fn basic_codes() -> Vec<FixtureCode> {
    vec![
        fixture_code(
            "github-work",
            "GitHub",
            "developer.fixture@example.org",
            "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
            &["Work"],
            "Primary developer account",
            true,
            false,
            0,
        ),
        fixture_code(
            "google-personal",
            "Google",
            "personal.fixture@example.org",
            "KRSXG5DSNFXGOIDBKRSXG5DSNFXGOIDB",
            &["Personal"],
            "Personal services",
            false,
            false,
            1,
        ),
        fixture_code(
            "microsoft-operations",
            "Microsoft",
            "operations.fixture@example.org",
            "MFRGGZDFMZTWQ2LKMFRGGZDFMZTWQ2LK",
            &["Work"],
            "Operations workspace",
            false,
            false,
            2,
        ),
        fixture_code(
            "stripe-finance",
            "Stripe",
            "billing.fixture@example.org",
            "ONSWG4TFOQXG64THONSWG4TFOQXG64TH",
            &["Finance"],
            "Fixture billing console",
            false,
            false,
            3,
        ),
        fixture_code(
            "dropbox-trashed",
            "Dropbox",
            "archive.fixture@example.org",
            "IFBEGRCFIZDUQSKKIFBEGRCFIZDUQSKK",
            &["Archive"],
            "Removed access pending review",
            false,
            true,
            4,
        ),
    ]
}

fn totp_codes() -> Vec<FixtureCode> {
    vec![fixture_code(
        "github-security",
        "GitHub",
        "security.fixture@example.org",
        "KVKFKRCPK5HVETCSKVKFKRCPK5HVETCS",
        &["Security"],
        "TOTP fixture sentinel",
        false,
        false,
        0,
    )]
}

fn recovery_codes() -> Vec<FixtureCode> {
    vec![fixture_code(
        "google-recovery",
        "Google",
        "recovery.fixture@example.org",
        "MZXW6YTBOI5DAMBRMZXW6YTBOI5DAMBR",
        &["Recovery"],
        "Must survive recovery-key password reset",
        true,
        false,
        0,
    )]
}

#[allow(clippy::too_many_arguments)]
fn fixture_code(
    id: &str,
    issuer: &str,
    account: &str,
    secret: &str,
    tags: &[&str],
    note: &str,
    pinned: bool,
    trashed: bool,
    position: i32,
) -> FixtureCode {
    FixtureCode {
        id: id.to_owned(),
        issuer: issuer.to_owned(),
        account: account.to_owned(),
        secret: secret.to_owned(),
        tags: tags.iter().map(|tag| (*tag).to_owned()).collect(),
        note: note.to_owned(),
        pinned,
        trashed,
        position,
    }
}

fn ensure_fixture_identity(email: &str) -> Result<()> {
    ensure!(
        email.starts_with("auth-maestro-fixture-") && email.ends_with("-v2@example.org"),
        "fixture email is not unmistakably test-only: {email}"
    );
    Ok(())
}

fn write_json_atomically(path: &Path, value: &impl Serialize) -> Result<()> {
    let parent = path
        .parent()
        .context("fixture output has no parent directory")?;
    fs::create_dir_all(parent).context("create fixture output directory")?;
    let temporary = path.with_extension("json.tmp");
    let payload = serde_json::to_vec_pretty(value).context("serialize fixture credentials")?;
    fs::write(&temporary, payload).context("write temporary fixture credentials")?;
    fs::rename(&temporary, path).context("publish fixture credentials")?;
    Ok(())
}

fn current_totp(secret: &str) -> String {
    let key = decode_base32(secret);
    let counter = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time before UNIX_EPOCH")
        .as_secs()
        / 30;

    let mut mac = HmacSha1::new_from_slice(&key).expect("invalid HMAC key");
    mac.update(&counter.to_be_bytes());
    let digest = mac.finalize().into_bytes();
    let offset = (digest[19] & 0x0f) as usize;
    let binary = ((digest[offset] as u32 & 0x7f) << 24)
        | ((digest[offset + 1] as u32) << 16)
        | ((digest[offset + 2] as u32) << 8)
        | digest[offset + 3] as u32;
    format!("{:06}", binary % 1_000_000)
}

fn decode_base32(secret: &str) -> Vec<u8> {
    let mut output = Vec::new();
    let mut buffer = 0u32;
    let mut bits = 0u8;

    for character in secret
        .chars()
        .filter(|character| !character.is_whitespace() && *character != '=')
    {
        let value = match character {
            'A'..='Z' => character as u8 - b'A',
            'a'..='z' => character as u8 - b'a',
            '2'..='7' => character as u8 - b'2' + 26,
            _ => panic!("invalid base32 character in TOTP secret: {character}"),
        } as u32;
        buffer = (buffer << 5) | value;
        bits += 5;
        while bits >= 8 {
            bits -= 8;
            output.push(((buffer >> bits) & 0xff) as u8);
        }
    }

    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialized_fixture_code_contains_display_state() {
        let code = &basic_codes()[0];
        let entity = serialize_code(code).unwrap();
        let raw_url: String = serde_json::from_str(&entity).unwrap();
        let url = Url::parse(&raw_url).unwrap();
        let query = url
            .query_pairs()
            .collect::<std::collections::HashMap<_, _>>();
        let display: serde_json::Value = serde_json::from_str(&query["codeDisplay"]).unwrap();

        assert_eq!(url.host_str(), Some("totp"));
        assert_eq!(query["issuer"], "GitHub");
        assert_eq!(display["pinned"], true);
        assert_eq!(display["tags"], serde_json::json!(["Work"]));
        assert_eq!(display["note"], "Primary developer account");
    }
}

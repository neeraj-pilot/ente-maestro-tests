use std::{
    env, fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, bail, ensure};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, CreateAccountParams, LoginParams,
    OtpPurpose, SecondFactorMethod, SetupTwoFactorParams, TotpPurpose,
};
use ente_core::crypto::SecretVec;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha1::Sha1;
use zeroize::Zeroizing;

const ENDPOINT: &str = "http://127.0.0.1:8080";
const EMAIL_OTP: &str = "123456";
const CLIENT_PACKAGE: &str = "io.ente.auth";
const NOTICE: &str = "Public local test fixtures. Never use these identities or credentials outside ephemeral local Museum instances.";

const BASIC_EMAIL: &str = "auth-maestro-fixture-basic-v1@example.org";
const BASIC_PASSWORD: &str = "EnteAuth-MaestroFixture-Basic-v1!";
const TOTP_EMAIL: &str = "auth-maestro-fixture-totp-v1@example.org";
const TOTP_PASSWORD: &str = "EnteAuth-MaestroFixture-Totp-v1!";
const RECOVERY_EMAIL: &str = "auth-maestro-fixture-recovery-v1@example.org";
const RECOVERY_PASSWORD: &str = "EnteAuth-MaestroFixture-Recovery-v1!";
const RECOVERED_PASSWORD: &str = "EnteAuth-MaestroFixture-Recovered-v1!";

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
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FixtureAccount {
    role: &'static str,
    email: &'static str,
    password: &'static str,
    recovery_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    totp_secret: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    recovered_password: Option<&'static str>,
    capabilities: Vec<&'static str>,
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
    let basic =
        create_fixture_account(endpoint, "basic", BASIC_EMAIL, BASIC_PASSWORD, false).await?;
    let totp = create_fixture_account(endpoint, "totp", TOTP_EMAIL, TOTP_PASSWORD, true).await?;
    let mut recovery = create_fixture_account(
        endpoint,
        "recovery",
        RECOVERY_EMAIL,
        RECOVERY_PASSWORD,
        false,
    )
    .await?;
    recovery.recovered_password = Some(RECOVERED_PASSWORD);

    let credentials = FixtureCredentials {
        classification: "PUBLIC_LOCAL_TEST_FIXTURE",
        notice: NOTICE,
        fixture_version: 1,
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
    println!("Verified fixture password and TOTP login credentials");
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
            .with_user_agent("ente-auth-maestro-fixture-verifier/1"),
    )
    .context("create Ente accounts client")?;
    let mut flow = AuthFlow::new(&client, &mut ui);
    flow.login(LoginParams {
        email: account.email,
        password: Zeroizing::new(account.password),
    })
    .await
    .context("verify fixture login")?;
    Ok(())
}

async fn create_fixture_account(
    endpoint: &str,
    role: &'static str,
    email: &'static str,
    password: &'static str,
    enable_totp: bool,
) -> Result<FixtureAccount> {
    ensure_fixture_identity(email)?;

    let client = AccountsClient::new(
        AccountsClientConfig::new(CLIENT_PACKAGE)
            .with_origin(endpoint)
            .with_user_agent("ente-auth-maestro-fixture-generator/1"),
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
        "basic" => vec!["passwordLogin", "accountSettings"],
        "totp" => vec!["passwordLogin", "totpLogin", "accountSettings"],
        "recovery" => vec!["recoveryKeyPasswordReset", "passwordLogin"],
        _ => bail!("unknown fixture role: {role}"),
    };

    Ok(FixtureAccount {
        role,
        email,
        password,
        recovery_key,
        totp_secret,
        recovered_password: None,
        capabilities,
    })
}

fn ensure_fixture_identity(email: &str) -> Result<()> {
    ensure!(
        email.starts_with("auth-maestro-fixture-") && email.ends_with("@example.org"),
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

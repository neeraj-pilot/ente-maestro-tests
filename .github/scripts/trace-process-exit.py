import ctypes
import os
import sys

pid = int(sys.argv[1])
libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
libc.ptrace.restype = ctypes.c_long
if libc.ptrace(0x4206, pid, None, 0x40) == -1:  # SEIZE, TRACEEXIT
    raise OSError(ctypes.get_errno(), "PTRACE_SEIZE")
print(f"Observing emulator pid {pid}", flush=True)
while True:
    _, status = os.waitpid(pid, 0x40000000)
    if os.WIFEXITED(status) or os.WIFSIGNALED(status):
        print(f"Emulator exit: {os.waitstatus_to_exitcode(status)}", flush=True)
        break
    signal = os.WSTOPSIG(status)
    if status >> 16 == 6:  # PTRACE_EVENT_EXIT
        event = ctypes.c_ulong()
        if libc.ptrace(0x4201, pid, None, ctypes.byref(event)) == -1:
            raise OSError(ctypes.get_errno(), "PTRACE_GETEVENTMSG")
        print(f"Emulator pending exit: {os.waitstatus_to_exitcode(event.value)}", flush=True)
        signal = 0
    else:
        print(f"Emulator signal: {signal}", flush=True)
    if libc.ptrace(7, pid, None, signal) == -1:  # CONT
        raise OSError(ctypes.get_errno(), "PTRACE_CONT")

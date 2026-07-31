"""Stand-in for a real service: binds a port, writes the kinds of output a real
terminal carries (colour, a carriage-return progress line), and can be told to die
after N seconds so the crash / self-heal path is exercised.

Note there is no SO_REUSEADDR: on Windows that flag lets two sockets share a port,
which would let a double-spawn bug pass the tests unnoticed."""
import socket
import sys
import threading
import time

port = int(sys.argv[1])
die_after = float(sys.argv[2]) if len(sys.argv) > 2 else 0

server = socket.socket()
server.bind(("127.0.0.1", port))
server.listen(5)

print(f"isatty={sys.stdout.isatty()}", flush=True)
print(f"dummy listening on {port}", flush=True)
print("\x1b[32mgreen line\x1b[0m", flush=True)
print("a line on stderr", file=sys.stderr, flush=True)
for step in range(1, 4):
    sys.stdout.write(f"\rloading {step}/3")
    sys.stdout.flush()
    time.sleep(0.1)
print(flush=True)

threading.Thread(target=lambda: [server.accept() for _ in iter(int, 1)], daemon=True).start()

start = time.time()
while True:
    if die_after and time.time() - start >= die_after:
        print("dying now", flush=True)
        sys.exit(3)
    print(f"tick {time.time() - start:.0f}", flush=True)
    time.sleep(1)

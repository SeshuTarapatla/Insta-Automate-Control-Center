"""Stand-in for a real service: binds a port, logs to stdout and stderr, and can be
told to die after N seconds so the crash/backoff path is exercised."""
import socket
import sys
import threading
import time

port = int(sys.argv[1])
die_after = float(sys.argv[2]) if len(sys.argv) > 2 else 0

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", port))
server.listen(5)
print(f"dummy listening on {port}", flush=True)
print("a line on stderr", file=sys.stderr, flush=True)

threading.Thread(target=lambda: [server.accept() for _ in iter(int, 1)], daemon=True).start()

start = time.time()
while True:
    if die_after and time.time() - start >= die_after:
        print("dying now", flush=True)
        sys.exit(3)
    print(f"tick {time.time() - start:.0f}", flush=True)
    time.sleep(1)

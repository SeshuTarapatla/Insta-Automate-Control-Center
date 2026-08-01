"""Exercise CP 5.1's Library API against the real `IA_DIR`. Strictly
read-only against the pipeline's own files: `LibraryCounts.seed()` only
`os.scandir`s directories, and `images.cache`/`thumbnail` only ever read the
source file and write into the agent's own cache dir — nothing under
`IA_DIR` is created, moved, or deleted."""
import sys
import time

from ia_agent import images
from ia_agent.library import folders
from ia_agent.library.counts import LibraryCounts


def main() -> int:
    print(f"IA_DIR: {folders.IA_DIR}")

    start = time.monotonic()
    counts = LibraryCounts()
    counts.seed()
    elapsed_ms = (time.monotonic() - start) * 1000
    print(f"seed() took {elapsed_ms:.0f} ms\n")

    folder_list = counts.folders()
    for row in folder_list:
        print(f"  {row['name']:16s} total={row['total']:<6d} entities={row['entities']}")

    non_flat = [row for row in folder_list if not row["flat"] and row["entities"] > 0]
    if not non_flat:
        print("\nno non-flat folder has any entities right now — nothing further to sample")
        return 0

    sample_folder = max(non_flat, key=lambda row: row["total"])["name"]
    print(f"\nsampling '{sample_folder}':")
    entities = counts.entities(sample_folder)
    for row in entities[:5]:
        print(f"  {row['root']:30s} {row['count']} file(s)")

    first_root = entities[0]["root"]
    directory = folders.FOLDERS[sample_folder].path / first_root
    first_file = next((f for f in directory.iterdir() if f.is_file()), None)
    if first_file is None:
        print(f"FAIL: {directory} listed {entities[0]['count']} files but none found on a real scan")
        return 1

    rel_path = first_file.relative_to(folders.IA_DIR).as_posix()
    print(f"\nfetching a real image: {rel_path}")
    key = images.cache(rel_path)
    if key is None:
        print("FAIL: cache() could not read the real file")
        return 1
    original = images.original(key)
    print(f"  cached at {original} ({original.stat().st_size} bytes)")

    thumb = images.thumbnail(key, 200)
    if thumb is None:
        print("FAIL: thumbnail() failed on a real image")
        return 1
    from PIL import Image

    with Image.open(thumb) as img:
        print(f"  thumbnail {thumb.name}: {img.size}")
        if img.width != 200:
            print(f"FAIL: expected thumbnail width 200, got {img.width}")
            return 1

    print("\nPASS: seeded real counts, listed real entities, cached and thumbnailed a real image")
    return 0


sys.exit(main())

"""Test tất cả ảnh mẫu."""
import sys, os
sys.path.insert(0, 'grading/engine')
import hi

hi.load_template('grading/engine/templates/template_default.json')

images = [
    'anh/1111.jpg',
    'anh/3e3accd013b192efcba0.jpg',
    'anh/da35b902e16f6031397e.jpg',
    'anh/f15599be46dfc7819ece.jpg',
]

for img_path in images:
    if not os.path.exists(img_path):
        print(f"\n[SKIP] {img_path} - khong ton tai")
        continue

    print(f"\n{'='*70}")
    print(f"  FILE: {img_path}")
    print(f"{'='*70}")

    try:
        r = hi.process_sheet(img_path, debug=True)
    except Exception as e:
        print(f"  [LOI] {e}")
        continue

    sbd = r.get('sbd', '?')
    made = r.get('made', '?')
    p1 = r.get('part1', {})
    p2 = r.get('part2', {})
    p3 = r.get('part3', {})

    p1_filled = sum(1 for v in p1.values() if v and v != 'X')
    p1_answers = {k: v for k, v in sorted(p1.items()) if v and v != 'X'}

    p2_filled = 0
    for q, subs in p2.items():
        for sub, val in subs.items():
            if val:
                p2_filled += 1

    p3_answers = {k: v for k, v in sorted(p3.items()) if v}

    print(f"\n  --- KET QUA ---")
    print(f"  SBD: {sbd}")
    print(f"  Ma de: {made}")
    print(f"  Part I:   {p1_filled}/40 cau  {p1_answers}")
    print(f"  Part II:  {p2_filled}/32 o")
    print(f"  Part III: {p3_answers if p3_answers else '(trong)'}")

print(f"\n{'='*70}")
print("  HOAN TAT")
print(f"{'='*70}")

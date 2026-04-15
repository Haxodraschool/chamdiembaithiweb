"""Test Method C hybrid results across all sample images."""
import sys; sys.path.insert(0, 'grading/engine')
import hi
hi.load_template('grading/engine/templates/template_default.json')

images = [
    'anh/3e3accd013b192efcba0.jpg',
    'anh/da35b902e16f6031397e.jpg',
    'anh/f15599be46dfc7819ece.jpg',
    'anh/1111.jpg',
]

print(f"{'Image':<40} {'Method':<25} {'P1':>4} {'SBD':<8} {'MD':<5}")
print("-" * 90)

for img in images:
    r = hi.process_sheet(img, debug=False)
    p1 = r.get('part1', {})
    n = sum(1 for v in p1.values() if v and v != 'X')
    m = r.get('detect_method', '?')
    sbd = r.get('sbd', '?')
    md = r.get('made', '?')
    print(f"{img:<40} {m:<25} {n:>2}/40 {sbd:<8} {md:<5}")

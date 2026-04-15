"""Diagnose why Q25-Q40 are not detected on filled sheets."""
import sys; sys.path.insert(0, 'grading/engine')
import hi, cv2
hi.load_template('grading/engine/templates/template_default.json')

for path in ['anh/1111.jpg']:
    print(f"\n{'='*70}")
    print(f"  {path}")
    print(f"{'='*70}")
    r = hi.process_sheet(path, debug=False)
    details = r.get('details', {}).get('part1', {})
    
    for q in range(1, 41):
        d = details.get(q, {})
        vals = list(d.values())
        mx = max(vals) if vals else 0
        best = max(d, key=d.get) if d else '-'
        status = r['part1'].get(q, '')
        flag = ' <<<MISS' if not status else ''
        print(f"  Q{q:2d}: {status or '-':>1}  max={mx:.3f}({best})  "
              f"A={d.get('A',0):.3f} B={d.get('B',0):.3f} "
              f"C={d.get('C',0):.3f} D={d.get('D',0):.3f}{flag}")

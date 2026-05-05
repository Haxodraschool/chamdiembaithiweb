"""Test engine on all 9 images in anh/ folder."""
import sys
import os
import glob
import time

sys.path.insert(0, 'grading/engine')
import hi as engine

IMAGE_DIR = r'anh'
images = sorted(glob.glob(os.path.join(IMAGE_DIR, '*.jpg')))

print(f"Found {len(images)} images to test\n")

results = []
for img_path in images:
    name = os.path.basename(img_path)
    print(f"\n{'='*60}")
    print(f"  Testing: {name}")
    print(f"{'='*60}")
    
    t0 = time.time()
    result = engine.process_sheet(img_path, debug=True)
    elapsed = time.time() - t0
    
    if result:
        p1 = result.get('part1', {})
        p2 = result.get('part2', {})
        p3 = result.get('part3', {})
        
        # Count detected answers
        p1_detected = sum(1 for a in p1.values() if a not in ('', 'X'))
        p1_blank = sum(1 for a in p1.values() if a == '')
        p1_multi = sum(1 for a in p1.values() if a == 'X')
        
        p2_detected = sum(1 for q, v in p2.items() 
                         if isinstance(v, dict) and any(vv not in ('', 'X') for vv in v.values()))
        
        p3_detected = sum(1 for v in p3.values() if v and v != '-')
        
        print(f"\n  ✓ SUCCESS ({elapsed:.1f}s)")
        print(f"    Method: {result.get('detect_method', '?')}")
        print(f"    SBD: {result.get('sbd', '?')}  |  Mã đề: {result.get('made', '?')}")
        print(f"    Score: {result.get('score', '?')}/{result.get('max_score', '?')}")
        print(f"    P1: {p1_detected}/40 detected, {p1_blank} blank, {p1_multi} multi")
        print(f"    P2: {p2_detected}/8 detected")
        print(f"    P3: {p3_detected}/6 detected")
        
        # Print P1 answers
        print(f"    P1 answers: ", end='')
        for q in range(1, 41):
            a = p1.get(q, '-')
            print(a, end=' ')
            if q % 10 == 0:
                print(f"\n              ", end='')
        print()
        
        results.append({
            'name': name,
            'success': True,
            'time': elapsed,
            'method': result.get('detect_method', '?'),
            'sbd': result.get('sbd', '?'),
            'made': result.get('made', '?'),
            'score': result.get('score', '?'),
            'p1_detected': p1_detected,
            'p1_blank': p1_blank,
            'p1_multi': p1_multi,
        })
    else:
        print(f"\n  ✗ FAILED ({elapsed:.1f}s)")
        results.append({
            'name': name,
            'success': False,
            'time': elapsed,
        })

# Summary
print(f"\n\n{'='*60}")
print(f"  SUMMARY")
print(f"{'='*60}")
success = sum(1 for r in results if r['success'])
print(f"  Success: {success}/{len(results)}")
print(f"  Total time: {sum(r['time'] for r in results):.1f}s")
print()
for r in results:
    if r['success']:
        print(f"  ✓ {r['name']:20s} | {r['method']:25s} | P1: {r['p1_detected']:2d}/40 blank={r['p1_blank']:2d} multi={r['p1_multi']:2d} | {r['time']:.1f}s")
    else:
        print(f"  ✗ {r['name']:20s} | FAILED | {r['time']:.1f}s")

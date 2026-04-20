"""Test OpenCV vs CNN solo on 7.jpg - detailed comparison log."""
import sys, os, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.path.insert(0, '.')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

from grading.engine.hi import (
    detect_paper_and_warp, preprocess, detect_section_offsets,
    PART1_COLS, PART1_NUM_ROWS, PART1_CHOICES, FILL_THRESHOLD,
    PART2_BLOCKS, PART2_STEP_X, PART2_STEP_Y, PART2_ROWS,
    is_bubble_filled, _predict_bubble_cnn, _load_bubble_cnn,
    _detect_filled_choices,
)

IMAGE_PATH = sys.argv[1] if len(sys.argv) > 1 else 'anh/7.jpg'

# Load & warp
image = __import__('cv2').imread(IMAGE_PATH)
result = detect_paper_and_warp(image, debug=False)
warped = result["warped"]
gray, thresh, cleaned = preprocess(warped)
offsets = detect_section_offsets(gray)

# Force load CNN
_load_bubble_cnn()

# Engine uses GRAY (not cleaned) for extract_part1/2
img = gray

print(f"Image: {IMAGE_PATH}")
print(f"Offsets: P1={offsets['part1']:+d}  P2={offsets['part2']:+d}  P3={offsets['part3']:+d}")
print()

# ===== PART 1 =====
print("=" * 100)
print(f"{'':3s} {'OpenCV':>30s}  {'CNN':>30s}  {'Winner':>10s}")
print(f"{'Q':3s} {'A':>7s}{'B':>7s}{'C':>7s}{'D':>7s} ans  {'A':>7s}{'B':>7s}{'C':>7s}{'D':>7s} ans  {'Final':>10s}")
print("-" * 100)

cv_total, cnn_total, final_total = 0, 0, 0

for cfg in PART1_COLS:
    sx, sy = cfg["start_x"], cfg["start_y"]
    dx, dy = cfg["step_x"], cfg["step_y"]
    q_start = cfg["q_start"]

    for row in range(cfg.get("num_rows", PART1_NUM_ROWS)):
        q = q_start + row
        cy = sy + row * dy + offsets["part1"]

        cv_ratios = {}
        cnn_ratios = {}
        hybrid_ratios = {}

        for ci, choice in enumerate(PART1_CHOICES):
            cx = sx + ci * dx
            _, ratio = is_bubble_filled(img, cx, cy)
            cnn_conf = _predict_bubble_cnn(img, cx, cy)
            cv_ratios[choice] = round(ratio, 3)
            cnn_ratios[choice] = round(cnn_conf, 3) if cnn_conf else 0.0
            hybrid_ratios[choice] = round(max(ratio, cnn_conf or 0), 3)

        # Detect answers from each engine
        cv_filled = _detect_filled_choices(cv_ratios)
        cnn_filled = _detect_filled_choices(cnn_ratios)
        hybrid_filled = _detect_filled_choices(hybrid_ratios)

        cv_ans = cv_filled[0] if len(cv_filled) == 1 else ('X' if len(cv_filled) > 1 else '_')
        cnn_ans = cnn_filled[0] if len(cnn_filled) == 1 else ('X' if len(cnn_filled) > 1 else '_')
        hyb_ans = hybrid_filled[0] if len(hybrid_filled) == 1 else ('X' if len(hybrid_filled) > 1 else '_')

        if cv_ans not in ('_', 'X'): cv_total += 1
        if cnn_ans not in ('_', 'X'): cnn_total += 1
        if hyb_ans not in ('_', 'X'): final_total += 1

        # Determine winner
        winner = "="
        if cv_ans != cnn_ans:
            if cv_ans == '_' and cnn_ans != '_':
                winner = "CNN+"
            elif cnn_ans == '_' and cv_ans != '_':
                winner = "CV+"
            elif cv_ans == 'X' and cnn_ans not in ('_', 'X'):
                winner = "CNN+"
            elif cnn_ans == 'X' and cv_ans not in ('_', 'X'):
                winner = "CV+"
            else:
                winner = "DIFF"

        mark = " " if cv_ans == cnn_ans else "*"

        cv_str = "".join(f"{cv_ratios[c]:7.3f}" for c in PART1_CHOICES)
        cnn_str = "".join(f"{cnn_ratios[c]:7.3f}" for c in PART1_CHOICES)

        print(f"Q{q:2d} {cv_str}  {cv_ans:>3s}  {cnn_str}  {cnn_ans:>3s}  {hyb_ans:>5s} {winner:>5s}{mark}")

print("-" * 100)
print(f"PART 1 detected: OpenCV={cv_total}/40  CNN={cnn_total}/40  Hybrid(max)={final_total}/40")

# ===== PART 2 =====
print()
print("=" * 100)
print("PART 2")
print("-" * 100)
cv2_total, cnn2_total, hyb2_total = 0, 0, 0

for blk in PART2_BLOCKS:
    q = blk["q"]
    sx, sy = blk["start_x"], blk["start_y"]

    for ri, label in enumerate(PART2_ROWS):
        cy = sy + ri * PART2_STEP_Y + offsets["part2"]

        # Dung
        _, r_d = is_bubble_filled(img, sx, cy)
        cnn_d = _predict_bubble_cnn(img, sx, cy) or 0.0
        # Sai
        _, r_s = is_bubble_filled(img, sx + PART2_STEP_X, cy)
        cnn_s = _predict_bubble_cnn(img, sx + PART2_STEP_X, cy) or 0.0

        cv_map = {"Dung": round(r_d, 3), "Sai": round(r_s, 3)}
        cnn_map = {"Dung": round(cnn_d, 3), "Sai": round(cnn_s, 3)}
        hyb_map = {"Dung": round(max(r_d, cnn_d), 3), "Sai": round(max(r_s, cnn_s), 3)}

        cv_f = _detect_filled_choices(cv_map)
        cnn_f = _detect_filled_choices(cnn_map)
        hyb_f = _detect_filled_choices(hyb_map)

        cv_a = cv_f[0] if len(cv_f) == 1 else ('X' if len(cv_f) > 1 else '_')
        cnn_a = cnn_f[0] if len(cnn_f) == 1 else ('X' if len(cnn_f) > 1 else '_')
        hyb_a = hyb_f[0] if len(hyb_f) == 1 else ('X' if len(hyb_f) > 1 else '_')

        if cv_a not in ('_', 'X'): cv2_total += 1
        if cnn_a not in ('_', 'X'): cnn2_total += 1
        if hyb_a not in ('_', 'X'): hyb2_total += 1

        winner = "=" if cv_a == cnn_a else ("CNN+" if cnn_a != '_' and cv_a == '_' else "CV+")
        mark = " " if cv_a == cnn_a else "*"

        print(f"  Q{q}{label} D={r_d:.3f}/{cnn_d:.3f} S={r_s:.3f}/{cnn_s:.3f}  "
              f"CV={cv_a:5s} CNN={cnn_a:5s} Hyb={hyb_a:5s} {winner}{mark}")

print("-" * 100)
print(f"PART 2 detected: OpenCV={cv2_total}/32  CNN={cnn2_total}/32  Hybrid(max)={hyb2_total}/32")

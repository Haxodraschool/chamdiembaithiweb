"""
Test the trained CNN bubble classifier on a new answer sheet image.
Compares CNN predictions vs current OpenCV engine results.

Usage:
  python -m grading.engine.test_bubble_cnn anh/1111.jpg
  python -m grading.engine.test_bubble_cnn anh/*.jpg
"""

import cv2
import numpy as np
import os
import sys
import glob
import io

import torch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from grading.engine.hi import (
    PART1_COLS, PART1_NUM_ROWS, PART1_CHOICES, BUBBLE_RADIUS,
    PART2_BLOCKS, PART2_STEP_X, PART2_STEP_Y, PART2_ROWS,
    SBD_COLS_X, MADE_COLS_X, SBD_MADE_DIGIT_Y,
    detect_section_offsets,
    extract_part1, extract_part2, extract_sbd_made,
)
from grading.engine.train_bubble_cnn import BubbleCNN
from grading.engine.extract_bubbles import load_and_warp, crop_bubble
from PIL import Image, ExifTags

MODEL_PATH = os.path.join(os.path.dirname(__file__), 'bubble_cnn.pth')
IMG_SIZE = 32


def load_model():
    """Load trained CNN model."""
    if not os.path.exists(MODEL_PATH):
        print(f"[ERROR] Model not found: {MODEL_PATH}")
        print("  Run: python -m grading.engine.train_bubble_cnn")
        sys.exit(1)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model = BubbleCNN().to(device)
    model.load_state_dict(torch.load(MODEL_PATH, map_location=device, weights_only=True))
    model.eval()
    return model, device


def predict_bubble(model, device, gray_img, cx, cy):
    """Predict if a bubble is filled using the CNN."""
    crop = crop_bubble(gray_img, cx, cy)
    if crop is None:
        return False, 0.0

    # Preprocess
    img = crop.astype(np.float32) / 255.0
    tensor = torch.from_numpy(img).unsqueeze(0).unsqueeze(0).to(device)  # (1,1,32,32)

    with torch.no_grad():
        out = model(tensor)
        probs = torch.softmax(out, dim=1)
        confidence = probs[0, 1].item()  # P(filled)

    return confidence > 0.5, confidence


def _pick_binary(conf_map, threshold=0.5):
    filled = [k for k, v in conf_map.items() if v > threshold]
    if len(filled) == 1:
        return filled[0]
    if len(filled) > 1:
        return "X"
    return ""


def _pick_digit(conf_map, threshold=0.5, gap=0.05):
    ordered = sorted(conf_map.items(), key=lambda x: x[1], reverse=True)
    top_d, top_c = ordered[0]
    second_c = ordered[1][1] if len(ordered) > 1 else 0.0
    if top_c < threshold:
        return "?"
    if (top_c - second_c) < gap:
        return "?"
    return str(top_d)


def test_image(model, device, image_path):
    """Test CNN vs OpenCV engine on one image."""
    print(f"\n{'='*60}")
    print(f"  Testing: {os.path.basename(image_path)}")
    print(f"{'='*60}")

    _, gray = load_and_warp(image_path)
    if gray is None:
        print("  FAILED to load/warp")
        return

    offsets = detect_section_offsets(gray)

    # Engine results (ground truth reference)
    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(io.BytesIO(), encoding='utf-8', errors='replace')
    p1_ans_engine, p1_det = extract_part1(gray, y_offset=offsets["part1"])
    p2_ans_engine, p2_det = extract_part2(gray, y_offset=offsets["part2"])
    sbd_engine, made_engine, sbd_made_det = extract_sbd_made(gray)
    sys.stdout, sys.stderr = old_out, old_err

    # CNN results
    p1_ans_cnn = {}
    agree = 0
    disagree = 0

    for cfg in PART1_COLS:
        sx, sy = cfg["start_x"], cfg["start_y"]
        dx, dy = cfg["step_x"], cfg["step_y"]
        q_start = cfg["q_start"]
        col_rows = cfg.get("num_rows", PART1_NUM_ROWS)

        for row in range(col_rows):
            q = q_start + row
            cy = sy + row * dy + offsets["part1"]
            cnn_ratios = {}

            for ci, choice in enumerate(PART1_CHOICES):
                cx = sx + ci * dx
                is_filled, confidence = predict_bubble(model, device, gray, cx, cy)
                cnn_ratios[choice] = confidence

            # Pick answer: highest confidence > 0.5
            best_choice = max(cnn_ratios, key=cnn_ratios.get)
            best_conf = cnn_ratios[best_choice]
            filled_choices = [ch for ch, c in cnn_ratios.items() if c > 0.5]

            if len(filled_choices) == 1:
                p1_ans_cnn[q] = filled_choices[0]
            elif len(filled_choices) > 1:
                p1_ans_cnn[q] = 'X'
            else:
                p1_ans_cnn[q] = ''

            engine_ans = p1_ans_engine.get(q, '')
            cnn_ans = p1_ans_cnn[q]

            if engine_ans == cnn_ans:
                agree += 1
            else:
                disagree += 1
                # Show disagreement
                eng_det = p1_det.get(q, {})
                print(f"  Q{q:2d}: Engine={engine_ans or '-':1s} CNN={cnn_ans or '-':1s} | "
                      f"Engine ratios: {eng_det} | CNN conf: {dict((k, f'{v:.2f}') for k,v in cnn_ratios.items())}")

    total = agree + disagree
    print(f"\n  Part I: {agree}/{total} agree ({agree/max(total,1)*100:.1f}%), {disagree} differ")

    # Side by side
    print(f"\n  {'Q':>3s} {'Engine':>7s} {'CNN':>5s}")
    print(f"  {'---':>3s} {'-------':>7s} {'-----':>5s}")
    for q in sorted(set(list(p1_ans_engine.keys()) + list(p1_ans_cnn.keys()))):
        e = p1_ans_engine.get(q, '')
        c = p1_ans_cnn.get(q, '')
        mark = ' *' if e != c else ''
        print(f"  {q:3d} {e or '-':>7s} {c or '-':>5s}{mark}")

    # Part II
    p2_agree = 0
    p2_disagree = 0
    for blk in PART2_BLOCKS:
        q = blk["q"]
        sx, sy = blk["start_x"], blk["start_y"]
        for ri, row_label in enumerate(PART2_ROWS):
            cy = sy + ri * PART2_STEP_Y + offsets["part2"]
            conf_map = {}
            for ci, col_label in enumerate(["Dung", "Sai"]):
                cx = sx + ci * PART2_STEP_X
                _, conf = predict_bubble(model, device, gray, cx, cy)
                conf_map[col_label] = conf
            cnn_ans = _pick_binary(conf_map, threshold=0.5)
            engine_ans = p2_ans_engine.get(q, {}).get(row_label, "")
            if engine_ans == cnn_ans:
                p2_agree += 1
            else:
                p2_disagree += 1
                print(
                    f"  P2 Q{q}{row_label}: Engine={engine_ans or '-'} CNN={cnn_ans or '-'} | "
                    f"CNN conf: {{'Dung': {conf_map['Dung']:.2f}, 'Sai': {conf_map['Sai']:.2f}}}"
                )

    p2_total = p2_agree + p2_disagree
    print(f"\n  Part II: {p2_agree}/{p2_total} agree ({p2_agree/max(p2_total,1)*100:.1f}%), {p2_disagree} differ")

    # SBD + Mã đề
    def _predict_digits(cols_x, prefix):
        pred = []
        for col_idx, cx in enumerate(cols_x):
            conf_map = {}
            for d, cy in enumerate(SBD_MADE_DIGIT_Y):
                _, conf = predict_bubble(model, device, gray, cx, cy)
                conf_map[d] = conf
            pred.append(_pick_digit(conf_map, threshold=0.5, gap=0.05))
        return "".join(pred)

    sbd_cnn = _predict_digits(SBD_COLS_X, "sbd")
    made_cnn = _predict_digits(MADE_COLS_X, "made")

    sbd_agree = sum(1 for a, b in zip(sbd_engine, sbd_cnn) if a == b)
    made_agree = sum(1 for a, b in zip(made_engine, made_cnn) if a == b)
    sbd_total = max(len(sbd_engine), len(sbd_cnn), 1)
    made_total = max(len(made_engine), len(made_cnn), 1)

    print(f"\n  SBD:  Engine={sbd_engine} | CNN={sbd_cnn} | Agree {sbd_agree}/{sbd_total}")
    print(f"  Ma de: Engine={made_engine} | CNN={made_cnn} | Agree {made_agree}/{made_total}")


def main():
    paths = []
    for arg in sys.argv[1:]:
        expanded = glob.glob(arg)
        paths.extend(expanded if expanded else [arg])

    if not paths:
        print("Usage: python -m grading.engine.test_bubble_cnn <image1> [image2] ...")
        sys.exit(1)

    model, device = load_model()
    print(f"Model loaded from: {MODEL_PATH}")
    print(f"Device: {device}")

    for path in paths:
        test_image(model, device, path)


if __name__ == '__main__':
    main()

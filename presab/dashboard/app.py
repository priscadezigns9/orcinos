"""
presab/dashboard/app.py
-----------------------
Flask + SocketIO backend for Presab Smart Attendance.
Serves:
  GET  /                     → Dashboard (requires access token via query ?token=)
  GET  /admin                → Enrollment admin portal
  GET  /video_feed           → MJPEG camera stream
  POST /api/engine/start     → Start recognition thread
  POST /api/engine/stop      → Stop recognition thread
  GET  /api/engine/status    → Engine status
  GET  /api/today            → Today's attendance log (JSON)
  GET  /api/stats            → Summary stats (JSON)
  GET  /api/enrolled         → Enrolled persons list (JSON)
  POST /api/enroll           → Enroll from uploaded photo(s)
  DELETE /api/enrolled/<id>  → Remove person from DB
  GET  /api/export           → Download today's CSV
  GET  /api/codes            → List access codes (admin only)
  POST /api/codes            → Create new access code
  DELETE /api/codes/<code>   → Revoke access code

Run: python app.py
"""

import os, csv, threading, pickle, json, base64, io, time
from datetime import date, datetime
from functools import wraps

from flask import Flask, render_template, jsonify, send_file, request, Response, abort
from flask_socketio import SocketIO
from PIL import Image
import numpy as np

# ── Path setup ───────────────────────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.join(BASE_DIR, '..')
DATA_DIR   = os.path.join(ROOT_DIR, 'data')
LOGS_DIR   = os.path.join(DATA_DIR, 'logs')
FACES_DIR  = os.path.join(DATA_DIR, 'faces')
PHOTOS_DIR = os.path.join(DATA_DIR, 'photos')
DB_FILE    = os.path.join(FACES_DIR, 'face_db.pkl')
CODES_FILE = os.path.join(DATA_DIR,  'access_codes.json')

import sys
sys.path.insert(0, ROOT_DIR)

# ── App setup ────────────────────────────────────────────────────────────────
app      = Flask(__name__)
app.config['SECRET_KEY'] = 'presab-orcinos-2026'
socketio = SocketIO(app, cors_allowed_origins='*', async_mode='eventlet')

# ── Shared state ─────────────────────────────────────────────────────────────
_recognition_thread = None
_stop_event         = threading.Event()
_camera_frame       = None          # Latest BGR frame (for MJPEG stream)
_camera_lock        = threading.Lock()
_engine_running     = False


# ═════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═════════════════════════════════════════════════════════════════════════════

def load_db():
    if not os.path.exists(DB_FILE):
        return {}
    with open(DB_FILE, 'rb') as f:
        return pickle.load(f)

def save_db(db):
    os.makedirs(FACES_DIR, exist_ok=True)
    with open(DB_FILE, 'wb') as f:
        pickle.dump(db, f)

def load_codes():
    if not os.path.exists(CODES_FILE):
        # Seed with the default demo code
        default = {
            'PRESAB2026': {
                'label': 'Default Demo',
                'role': 'demo',
                'created_at': datetime.now().isoformat(),
                'active': True
            }
        }
        os.makedirs(DATA_DIR, exist_ok=True)
        json.dump(default, open(CODES_FILE, 'w'), indent=2)
        return default
    return json.load(open(CODES_FILE))

def save_codes(codes):
    json.dump(codes, open(CODES_FILE, 'w'), indent=2)

def valid_code(code):
    codes = load_codes()
    entry = codes.get(code)
    return entry and entry.get('active', False)

def admin_auth():
    """Verify admin key from header or query param."""
    key = request.headers.get('X-Admin-Key') or request.args.get('admin_key')
    return key == os.environ.get('PRESAB_ADMIN_KEY', 'orcinos-admin-2026')

def require_admin(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not admin_auth():
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated


# ═════════════════════════════════════════════════════════════════════════════
# CAMERA + RECOGNITION ENGINE
# ═════════════════════════════════════════════════════════════════════════════

def recognition_loop(socketio, stop_event):
    """
    Runs in a background thread.
    - Opens webcam
    - Runs face_recognition on each frame
    - Writes latest frame to _camera_frame for MJPEG stream
    - Emits attendance_event over WebSocket when someone is marked
    """
    global _camera_frame, _engine_running

    try:
        import face_recognition
        import cv2
    except ImportError:
        print('[Presab] ⚠️  face_recognition or cv2 not installed. Engine cannot start.')
        return

    db = load_db()
    if not db:
        print('[Presab] No enrolled faces. Streaming camera only.')

    known_ids       = list(db.keys())
    known_encodings = [db[pid]['encoding'] for pid in known_ids]
    known_names     = [db[pid]['name']     for pid in known_ids]
    known_roles     = [db[pid]['role']     for pid in known_ids]

    log_path = os.path.join(LOGS_DIR, f"attendance_{date.today().isoformat()}.csv")
    os.makedirs(LOGS_DIR, exist_ok=True)
    if not os.path.exists(log_path):
        with open(log_path, 'w', newline='') as f:
            csv.writer(f).writerow(['id', 'name', 'role', 'timestamp', 'status'])

    marked_today      = set()
    last_marked_time  = {}
    TOLERANCE         = 0.50
    FRAME_SCALE       = 0.5
    MARK_COOLDOWN     = 60

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print('[Presab] ❌ Cannot access webcam.')
        return

    _engine_running = True
    print(f'[Presab] ✅ Engine started. {len(known_ids)} people enrolled.')

    while not stop_event.is_set():
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.05)
            continue

        small     = cv2.resize(frame, (0, 0), fx=FRAME_SCALE, fy=FRAME_SCALE)
        rgb_small = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)

        locations = face_recognition.face_locations(rgb_small, model='hog')
        encodings = face_recognition.face_encodings(rgb_small, locations)

        for enc, loc in zip(encodings, locations):
            scale = int(1 / FRAME_SCALE)
            top, right, bottom, left = [v * scale for v in loc]

            if known_encodings:
                distances = face_recognition.face_distance(known_encodings, enc)
                best_idx  = int(np.argmin(distances))
                best_dist = distances[best_idx]
            else:
                best_dist = 1.0

            if best_dist <= TOLERANCE:
                pid   = known_ids[best_idx]
                name  = known_names[best_idx]
                role  = known_roles[best_idx]
                color = (124, 58, 237)  # Purple

                now  = datetime.now()
                last = last_marked_time.get(pid)
                if last is None or (now - last).seconds >= MARK_COOLDOWN:
                    if pid not in marked_today:
                        marked_today.add(pid)
                        with open(log_path, 'a', newline='') as f:
                            csv.writer(f).writerow(
                                [pid, name, role, now.strftime('%Y-%m-%d %H:%M:%S'), 'present'])
                        socketio.emit('attendance_event', {
                            'id': pid, 'name': name, 'role': role,
                            'time': now.strftime('%H:%M'), 'status': 'present'
                        })
                        print(f'[Presab] ✅ {name} marked present')
                    last_marked_time[pid] = now

                cv2.rectangle(frame, (left, top), (right, bottom), color, 2)
                cv2.rectangle(frame, (left, bottom - 28), (right, bottom), color, cv2.FILLED)
                cv2.putText(frame, f'{name} ✓', (left + 6, bottom - 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)
            else:
                cv2.rectangle(frame, (left, top), (right, bottom), (0, 0, 200), 2)
                cv2.rectangle(frame, (left, bottom - 28), (right, bottom), (0, 0, 200), cv2.FILLED)
                cv2.putText(frame, 'Unknown', (left + 6, bottom - 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)

        # HUD overlay
        cv2.putText(frame, f'Presab  |  {date.today()}  |  {len(marked_today)} present',
                    (10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (124, 58, 237), 2)

        with _camera_lock:
            _camera_frame = frame.copy()

    cap.release()
    _engine_running = False
    print('[Presab] Engine stopped.')


def generate_mjpeg():
    """Yield MJPEG frames from the latest camera frame."""
    import cv2
    while True:
        with _camera_lock:
            frame = _camera_frame
        if frame is None:
            time.sleep(0.05)
            continue
        ret, buf = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
        if not ret:
            continue
        yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + buf.tobytes() + b'\r\n')
        time.sleep(1 / 20)   # ~20 fps


# ═════════════════════════════════════════════════════════════════════════════
# ROUTES — PAGES
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/admin')
@require_admin
def admin():
    return render_template('admin.html')


# ═════════════════════════════════════════════════════════════════════════════
# ROUTES — CAMERA STREAM
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/video_feed')
def video_feed():
    return Response(generate_mjpeg(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')


# ═════════════════════════════════════════════════════════════════════════════
# ROUTES — ENGINE CONTROL
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/api/engine/start', methods=['POST'])
def start_engine():
    global _recognition_thread, _stop_event
    if _recognition_thread and _recognition_thread.is_alive():
        return jsonify({'status': 'already_running'})
    _stop_event.clear()
    _recognition_thread = threading.Thread(
        target=recognition_loop,
        kwargs={'socketio': socketio, 'stop_event': _stop_event},
        daemon=True
    )
    _recognition_thread.start()
    return jsonify({'status': 'started'})

@app.route('/api/engine/stop', methods=['POST'])
def stop_engine():
    _stop_event.set()
    return jsonify({'status': 'stopped'})

@app.route('/api/engine/status')
def engine_status():
    running = _recognition_thread is not None and _recognition_thread.is_alive()
    return jsonify({'running': running})


# ═════════════════════════════════════════════════════════════════════════════
# ROUTES — ATTENDANCE DATA
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/api/today')
def today_log():
    log_path = os.path.join(LOGS_DIR, f"attendance_{date.today().isoformat()}.csv")
    records  = []
    if os.path.exists(log_path):
        with open(log_path, newline='') as f:
            records = list(csv.DictReader(f))
    return jsonify(records)

@app.route('/api/stats')
def stats():
    log_path = os.path.join(LOGS_DIR, f"attendance_{date.today().isoformat()}.csv")
    total = students = staff = 0
    if os.path.exists(log_path):
        with open(log_path, newline='') as f:
            for row in csv.DictReader(f):
                total += 1
                if row.get('role') == 'student': students += 1
                elif row.get('role') == 'staff':  staff    += 1

    db       = load_db()
    enrolled = len(db)
    return jsonify({
        'date': date.today().isoformat(),
        'total_present':    total,
        'students_present': students,
        'staff_present':    staff,
        'enrolled':         enrolled,
        'absent':           max(0, enrolled - total)
    })

@app.route('/api/export')
def export():
    log_path = os.path.join(LOGS_DIR, f"attendance_{date.today().isoformat()}.csv")
    if not os.path.exists(log_path):
        return jsonify({'error': 'No log for today'}), 404
    return send_file(log_path, as_attachment=True,
                     download_name=f"presab_attendance_{date.today().isoformat()}.csv")


# ═════════════════════════════════════════════════════════════════════════════
# ROUTES — ENROLLMENT (PHOTO UPLOAD)
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/api/enrolled')
def enrolled_list():
    db = load_db()
    result = []
    for pid, data in db.items():
        result.append({
            'id':          pid,
            'name':        data.get('name', ''),
            'role':        data.get('role', ''),
            'enrolled_at': data.get('enrolled_at', '')
        })
    return jsonify(sorted(result, key=lambda x: x['name']))

@app.route('/api/enroll', methods=['POST'])
@require_admin
def enroll():
    """
    Enroll a person from one or more uploaded photos.
    Accepts multipart/form-data:
      - person_id (str, required)
      - name      (str, required)
      - role      (student|staff|visitor)
      - photos[]  (one or more image files)
    """
    try:
        import face_recognition
    except ImportError:
        return jsonify({'error': 'face_recognition not installed on server'}), 500

    person_id = request.form.get('person_id', '').strip()
    name      = request.form.get('name', '').strip()
    role      = request.form.get('role', 'student').strip()

    if not person_id or not name:
        return jsonify({'error': 'person_id and name are required'}), 400

    files = request.files.getlist('photos')
    if not files:
        return jsonify({'error': 'At least one photo is required'}), 400

    encodings = []
    os.makedirs(PHOTOS_DIR, exist_ok=True)

    for i, file in enumerate(files):
        try:
            img_pil  = Image.open(file.stream).convert('RGB')
            img_np   = np.array(img_pil)
            locs     = face_recognition.face_locations(img_np, model='hog')
            encs     = face_recognition.face_encodings(img_np, locs)

            if not encs:
                continue  # No face in this photo — skip

            encodings.append(encs[0])

            # Save the photo for audit trail
            photo_path = os.path.join(PHOTOS_DIR, f"{person_id}_{i}.jpg")
            img_pil.save(photo_path, 'JPEG')

        except Exception as e:
            print(f'[Presab] Enrollment photo {i} error: {e}')
            continue

    if not encodings:
        return jsonify({'error': 'No faces detected in any uploaded photo. Try clearer, well-lit images.'}), 422

    # Average all encodings for robustness
    avg_encoding = np.mean(encodings, axis=0)

    db = load_db()
    db[person_id] = {
        'name':        name,
        'role':        role,
        'encoding':    avg_encoding,
        'enrolled_at': datetime.now().isoformat(),
        'photo_count': len(encodings)
    }
    save_db(db)

    print(f'[Presab] ✅ Enrolled {name} ({person_id}) — {len(encodings)} photo(s) used.')
    return jsonify({
        'success':     True,
        'id':          person_id,
        'name':        name,
        'role':        role,
        'photos_used': len(encodings),
        'total_enrolled': len(db)
    })

@app.route('/api/enrolled/<person_id>', methods=['DELETE'])
@require_admin
def remove_enrolled(person_id):
    db = load_db()
    if person_id not in db:
        return jsonify({'error': 'ID not found'}), 404
    name = db[person_id]['name']
    del db[person_id]
    save_db(db)
    return jsonify({'success': True, 'removed': name, 'total_enrolled': len(db)})


# ═════════════════════════════════════════════════════════════════════════════
# ROUTES — ACCESS CODES
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/api/codes', methods=['GET'])
@require_admin
def list_codes():
    return jsonify(load_codes())

@app.route('/api/codes', methods=['POST'])
@require_admin
def create_code():
    body  = request.get_json() or {}
    code  = body.get('code', '').strip().upper()
    label = body.get('label', 'Unnamed').strip()
    role  = body.get('role', 'demo').strip()

    if not code:
        return jsonify({'error': 'code is required'}), 400

    codes = load_codes()
    if code in codes:
        return jsonify({'error': 'Code already exists'}), 409

    codes[code] = {
        'label':      label,
        'role':       role,
        'created_at': datetime.now().isoformat(),
        'active':     True
    }
    save_codes(codes)
    return jsonify({'success': True, 'code': code})

@app.route('/api/codes/<code>', methods=['DELETE'])
@require_admin
def revoke_code(code):
    codes = load_codes()
    if code not in codes:
        return jsonify({'error': 'Code not found'}), 404
    codes[code]['active'] = False
    save_codes(codes)
    return jsonify({'success': True, 'revoked': code})

@app.route('/api/codes/validate', methods=['POST'])
def validate_code():
    body = request.get_json() or {}
    code = body.get('code', '').strip().upper()
    if valid_code(code):
        return jsonify({'valid': True})
    return jsonify({'valid': False}), 401


# ═════════════════════════════════════════════════════════════════════════════
# SOCKETIO
# ═════════════════════════════════════════════════════════════════════════════

@socketio.on('connect')
def on_connect():
    print('[Presab] Dashboard client connected')

@socketio.on('request_stats')
def on_request_stats():
    # Push current stats to requesting client
    log_path = os.path.join(LOGS_DIR, f"attendance_{date.today().isoformat()}.csv")
    total = students = staff = 0
    if os.path.exists(log_path):
        with open(log_path, newline='') as f:
            for row in csv.DictReader(f):
                total += 1
                if row.get('role') == 'student': students += 1
                elif row.get('role') == 'staff':  staff    += 1
    db = load_db()
    socketio.emit('stats_update', {
        'total_present':    total,
        'students_present': students,
        'staff_present':    staff,
        'enrolled':         len(db),
        'absent':           max(0, len(db) - total)
    })


# ═════════════════════════════════════════════════════════════════════════════
# STARTUP
# ═════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    for d in [LOGS_DIR, FACES_DIR, PHOTOS_DIR]:
        os.makedirs(d, exist_ok=True)
    load_codes()  # Seed default code if missing
    print('[Presab] ✅ Dashboard running at http://localhost:5050')
    print('[Presab] ✅ Admin portal at  http://localhost:5050/admin?admin_key=orcinos-admin-2026')
    socketio.run(app, host='0.0.0.0', port=5050, debug=False)

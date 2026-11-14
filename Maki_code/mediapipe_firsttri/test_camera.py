
import cv2
from camera_manager import CameraManager

manager = CameraManager()

# Reemplaza con la URL que utilizas actualmente
manager.add_camera(
    "camera_1",
    "http://10.154.236.136/stream"
)

manager.start_camera("camera_1")

try:
    while True:
        frame = manager.get_frame("camera_1")

        if frame is not None:
            cv2.imshow("MaKi - Camera 1", frame)

        if cv2.waitKey(1) & 0xFF == 27:
            break

finally:
    manager.stop_all()
    cv2.destroyAllWindows()

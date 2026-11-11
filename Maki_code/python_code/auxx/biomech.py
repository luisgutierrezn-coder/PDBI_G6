
import math

def raw_distance(point1, point2):

    dx = point2["x"] - point1["x"]
    dy = point2["y"] - point1["y"]

    return math.sqrt(dx**2 + dy**2)


def normalized_distance(point1, point2, reference_distance):

    distance = raw_distance(point1, point2)

    if reference_distance == 0:
        return None

    return distance / reference_distance


def calculate_angle(point1, point2, point3): # p1 vertice p2

    v1 = (
        point1["x"] - point2["x"],
        point1["y"] - point2["y"]
    )

    v2 = (
        point3["x"] - point2["x"],
        point3["y"] - point2["y"]
    )

    dot_product = v1[0] * v2[0] + v1[1] * v2[1]

    magnitude1 = math.sqrt(v1[0]**2 + v1[1]**2)
    magnitude2 = math.sqrt(v2[0]**2 + v2[1]**2)

    if magnitude1 == 0 or magnitude2 == 0:
        return None

    cos_angle = dot_product / (magnitude1 * magnitude2)

    # Evitar errores numéricos
    cos_angle = max(-1, min(1, cos_angle))

    angle = math.degrees(math.acos(cos_angle))

    return angle

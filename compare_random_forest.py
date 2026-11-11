import csv
import random
from datetime import datetime
from pathlib import Path


ROOT = Path(r"C:\Users\subin\OneDrive\Desktop\20261111")
DATASET = ROOT / "wind_dataset.csv"
OUTPUT = ROOT / "predictions_model_comparison.csv"
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
FEATURES = (
    "current_wind_speed_ms",
    "wind_speed_1h_before_ms",
    "wind_speed_2h_before_ms",
    "current_temperature_C",
    "current_humidity_pct",
)


def parse_time(value):
    return datetime.strptime(value, TIME_FORMAT)


def fit_linear(features, targets):
    size = len(features[0]) + 1
    matrix = [[0.0] * size for _ in range(size)]
    rhs = [0.0] * size
    for row, target in zip(features, targets):
        x = [1.0] + row
        for i in range(size):
            rhs[i] += x[i] * target
            for j in range(size):
                matrix[i][j] += x[i] * x[j]
    for k in range(size):
        pivot = max(range(k, size), key=lambda i: abs(matrix[i][k]))
        matrix[k], matrix[pivot] = matrix[pivot], matrix[k]
        rhs[k], rhs[pivot] = rhs[pivot], rhs[k]
        for i in range(k + 1, size):
            factor = matrix[i][k] / matrix[k][k]
            for j in range(k, size):
                matrix[i][j] -= factor * matrix[k][j]
            rhs[i] -= factor * rhs[k]
    coefficients = [0.0] * size
    for i in range(size - 1, -1, -1):
        coefficients[i] = (
            rhs[i] - sum(matrix[i][j] * coefficients[j] for j in range(i + 1, size))
        ) / matrix[i][i]
    return coefficients


class Tree:
    def __init__(self, value=None, feature=None, threshold=None, left=None, right=None):
        self.value = value
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right

    def predict(self, row):
        if self.value is not None:
            return self.value
        if row[self.feature] <= self.threshold:
            return self.left.predict(row)
        return self.right.predict(row)


def build_tree(rows, targets, depth, rng):
    value = sum(targets) / len(targets)
    if depth == 0 or len(rows) < 10 or len(set(targets)) == 1:
        return Tree(value=value)
    feature_count = len(rows[0])
    feature_indices = rng.sample(range(feature_count), feature_count)
    best = None
    parent_error = sum((target - value) ** 2 for target in targets)
    for feature in feature_indices:
        ordered = sorted(
            ((row[feature], target, index) for index, (row, target) in enumerate(zip(rows, targets))),
            key=lambda item: item[0],
        )
        left_sum = 0.0
        left_sq = 0.0
        right_sum = sum(targets)
        right_sq = sum(target * target for target in targets)
        for index in range(len(ordered) - 1):
            x, target, _ = ordered[index]
            left_sum += target
            left_sq += target * target
            right_sum -= target
            right_sq -= target * target
            if x == ordered[index + 1][0]:
                continue
            left_count = index + 1
            right_count = len(ordered) - left_count
            if left_count < 5 or right_count < 5:
                continue
            error = (
                left_sq - left_sum * left_sum / left_count
                + right_sq - right_sum * right_sum / right_count
            )
            if best is None or error < best[0]:
                best = (error, feature, (x + ordered[index + 1][0]) / 2)
    if best is None or best[0] >= parent_error:
        return Tree(value=value)
    _, feature, threshold = best
    left = [(row, target) for row, target in zip(rows, targets) if row[feature] <= threshold]
    right = [(row, target) for row, target in zip(rows, targets) if row[feature] > threshold]
    return Tree(
        feature=feature,
        threshold=threshold,
        left=build_tree([item[0] for item in left], [item[1] for item in left], depth - 1, rng),
        right=build_tree([item[0] for item in right], [item[1] for item in right], depth - 1, rng),
    )


def fit_forest(features, targets, seed=42):
    rng = random.Random(seed)
    trees = []
    for _ in range(100):
        sample_indices = [rng.randrange(len(features)) for _ in features]
        trees.append(
            build_tree(
                [features[index] for index in sample_indices],
                [targets[index] for index in sample_indices],
                6,
                rng,
            )
        )
    return trees


with DATASET.open("r", encoding="utf-8-sig", newline="") as handle:
    rows = sorted(csv.DictReader(handle), key=lambda row: parse_time(row["target_time"]))
train = [row for row in rows if datetime(2023, 1, 1) <= parse_time(row["target_time"]) < datetime(2024, 12, 1)]
evaluation = [row for row in rows if datetime(2024, 12, 1) <= parse_time(row["target_time"]) < datetime(2025, 1, 1)]
x_train = [[float(row[name]) for name in FEATURES] for row in train]
y_train = [float(row["target_wind_speed_ms"]) for row in train]
x_eval = [[float(row[name]) for name in FEATURES] for row in evaluation]
y_eval = [float(row["target_wind_speed_ms"]) for row in evaluation]

linear_coefficients = fit_linear(x_train, y_train)
linear_predictions = [
    max(0.0, linear_coefficients[0] + sum(c * x for c, x in zip(linear_coefficients[1:], row)))
    for row in x_eval
]
forest = fit_forest(x_train, y_train)
forest_predictions = [
    max(0.0, sum(tree.predict(row) for tree in forest) / len(forest)) for row in x_eval
]
baseline_predictions = [float(row["current_wind_speed_ms"]) for row in evaluation]

with OUTPUT.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=[
        "prediction_time", "target_time", "actual_wind_speed_ms",
        "baseline_current_wind_speed_ms", "linear_regression_prediction_ms",
        "random_forest_prediction_ms",
    ])
    writer.writeheader()
    for row, baseline, linear, forest_value in zip(
        evaluation, baseline_predictions, linear_predictions, forest_predictions
    ):
        writer.writerow({
            "prediction_time": row["prediction_time"],
            "target_time": row["target_time"],
            "actual_wind_speed_ms": row["target_wind_speed_ms"],
            "baseline_current_wind_speed_ms": row["current_wind_speed_ms"],
            "linear_regression_prediction_ms": f"{linear:.10f}",
            "random_forest_prediction_ms": f"{forest_value:.10f}",
        })

mae = lambda predictions: sum(abs(prediction - actual) for prediction, actual in zip(predictions, y_eval)) / len(y_eval)
baseline_mae = mae(baseline_predictions)
linear_mae = mae(linear_predictions)
forest_mae = mae(forest_predictions)
print(f"TRAIN_ROWS={len(train)}")
print(f"EVAL_ROWS={len(evaluation)}")
print(f"BASELINE_MAE={baseline_mae:.10f}")
print(f"LINEAR_REGRESSION_MAE={linear_mae:.10f}")
print(f"RANDOM_FOREST_MAE={forest_mae:.10f}")
print(f"FOREST_MINUS_BASELINE={forest_mae - baseline_mae:.10f}")
print(f"FOREST_MINUS_LINEAR={forest_mae - linear_mae:.10f}")
print(f"OUTPUT={OUTPUT}")
print("FIRST_EVALUATION_ROW:")
print(evaluation[0]["prediction_time"], evaluation[0]["target_time"])
print(y_eval[0], baseline_predictions[0], linear_predictions[0], forest_predictions[0])

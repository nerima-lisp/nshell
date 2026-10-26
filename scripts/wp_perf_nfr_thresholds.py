"""Acceptance thresholds for NFR-01 through NFR-07 performance measurements."""

NFR_THRESHOLDS = {
    "01": {"limit": 150.0, "unit": "ms", "statistic": "median"},
    "02": {"limit": 15.0, "unit": "ms", "statistic": "absolute difference of medians"},
    "03": {"limit": 5_000.0, "unit": "ms", "statistic": "median"},
    "04": {"limit": 60.0, "unit": "ms", "statistic": "median"},
    "05": {"limit": 16.0, "unit": "ms", "statistic": "p99"},
    "06": {"limit": 100.0, "unit": "ms", "statistic": "median"},
    "07": {"limit": 150.0, "unit": "MB", "statistic": "median"},
}

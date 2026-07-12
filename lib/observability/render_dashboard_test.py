from __future__ import annotations

import unittest

from render_dashboard import render


class RenderDashboardTests(unittest.TestCase):
    def test_replaces_templates_and_adds_top_level_metadata(self) -> None:
        dashboard = {
            "templating": {
                "list": [
                    {"name": "source"},
                    {"name": "retained"},
                ]
            },
            "panels": [
                {
                    "datasource": "${source}",
                    "expr": 'rate(metric{job="$job"}[$__rate_interval])',
                }
            ],
            "tags": ["upstream"],
        }
        specification = {
            "replacements": [
                {"key": "source", "value": "prometheus"},
                {"key": "job", "value": "node"},
            ],
            "tags": ["managed"],
            "extraAttrs": {"uid": "managed-dashboard"},
        }

        rendered = render(dashboard, specification)

        self.assertEqual(rendered["templating"]["list"], [{"name": "retained"}])
        self.assertEqual(rendered["panels"][0]["datasource"], "prometheus")
        self.assertEqual(
            rendered["panels"][0]["expr"], 'rate(metric{job="node"}[4m])'
        )
        self.assertEqual(rendered["tags"], ["managed"])
        self.assertEqual(rendered["uid"], "managed-dashboard")


if __name__ == "__main__":
    unittest.main()

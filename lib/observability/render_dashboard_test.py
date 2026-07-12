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

    def test_accepts_dashboards_without_a_template_list(self) -> None:
        specification = {
            "replacements": [{"key": "source", "value": "prometheus"}],
            "tags": ["managed"],
            "extraAttrs": {},
        }

        for templating in (None, {}, {"list": None}):
            with self.subTest(templating=templating):
                dashboard = {"title": "Simple dashboard"}
                if templating is not None:
                    dashboard["templating"] = templating

                rendered = render(dashboard, specification)

                self.assertEqual(rendered["title"], "Simple dashboard")
                self.assertEqual(rendered["tags"], ["managed"])

    def test_preserves_non_object_template_entries(self) -> None:
        dashboard = {
            "templating": {
                "list": ["unexpected", {"name": "source"}, {"name": "retained"}]
            }
        }
        specification = {
            "replacements": [{"key": "source", "value": "prometheus"}],
            "tags": [],
            "extraAttrs": {},
        }

        rendered = render(dashboard, specification)

        self.assertEqual(
            rendered["templating"]["list"],
            ["unexpected", {"name": "retained"}],
        )


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Regression checks for Herdr master-layout topology validation."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.machinery
import importlib.util
from io import StringIO
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).parents[1] / "herdr/.local/bin/herdr-master"
LOADER = importlib.machinery.SourceFileLoader("herdr_master", str(MODULE_PATH))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MASTER = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = MASTER
sys.dont_write_bytecode = True
LOADER.exec_module(MASTER)


def layout(binary_stack: bool) -> dict:
    area = {"x": 0, "y": 0, "width": 100, "height": 80}
    panes = [{"pane_id": "master", "rect": {"x": 0, "y": 0, "width": 60, "height": 80}}]
    panes.extend(
        {
            "pane_id": f"child-{index}",
            "rect": {"x": 60, "y": (index - 1) * 20, "width": 40, "height": 20},
        }
        for index in range(1, 5)
    )
    splits = [{"direction": "right", "ratio": 0.6, "rect": area}]
    if binary_stack:
        splits.extend(
            [
                {"direction": "down", "ratio": 0.5, "rect": {"x": 60, "y": 0, "width": 40, "height": 80}},
                {"direction": "down", "ratio": 0.5, "rect": {"x": 60, "y": 0, "width": 40, "height": 40}},
                {"direction": "down", "ratio": 0.5, "rect": {"x": 60, "y": 40, "width": 40, "height": 40}},
            ]
        )
    else:
        splits.extend(
            [
                {"direction": "down", "ratio": 0.25, "rect": {"x": 60, "y": 0, "width": 40, "height": 80}},
                {"direction": "down", "ratio": 1 / 3, "rect": {"x": 60, "y": 20, "width": 40, "height": 60}},
                {"direction": "down", "ratio": 0.5, "rect": {"x": 60, "y": 40, "width": 40, "height": 40}},
            ]
        )
    return {
        "area": area,
        "panes": panes,
        "splits": splits,
        "zoomed": False,
        "tab_id": "scratch-tab",
    }


class HerdrMasterTopologyTests(unittest.TestCase):
    def test_chain_stack_is_supported(self) -> None:
        _, panes, stack_splits, root = MASTER.canonical_layout(layout(binary_stack=False))
        self.assertEqual(len(panes), 5)
        self.assertEqual(len(stack_splits), 3)
        self.assertIsNotNone(root)

    def test_binary_right_stack_is_rejected(self) -> None:
        with self.assertRaisesRegex(MASTER.MasterError, "simple vertical chain"):
            MASTER.canonical_layout(layout(binary_stack=True))

    def test_status_lists_panes_for_unsupported_topology(self) -> None:
        source = layout(binary_stack=True)
        source["tab_id"] = "scratch-tab"
        pane_state = [
            {"pane_id": pane["pane_id"], "tab_id": "scratch-tab", "agent_status": "idle"}
            for pane in source["panes"]
        ]
        data = {"layouts": [source], "panes": pane_state}
        output = StringIO()
        with redirect_stdout(output):
            MASTER.show_status(data, {"label": "scratch"}, "scratch-tab")
        rendered = output.getvalue()
        self.assertIn("no master layout in this tab", rendered)
        for pane in source["panes"]:
            self.assertIn(pane["pane_id"], rendered)

    def test_spawn_partial_failure_names_created_pane(self) -> None:
        source = {
            "area": {"x": 0, "y": 0, "width": 100, "height": 80},
            "panes": [{"pane_id": "master", "rect": {"x": 0, "y": 0, "width": 100, "height": 80}}],
            "splits": [],
            "zoomed": False,
            "tab_id": "scratch-tab",
        }
        data = {
            "tabs": [{"tab_id": "scratch-tab", "label": "scratch"}],
            "panes": [{"pane_id": "master", "tab_id": "scratch-tab"}],
            "layouts": [source],
            "focused_tab_id": "scratch-tab",
        }
        output = StringIO()
        with (
            patch.object(sys, "argv", ["herdr-master", "spawn", "--tab", "scratch-tab", "--label", "reviewer", "--cwd", "/tmp", "--", "true"]),
            patch.object(MASTER, "snapshot", return_value=data),
            patch.object(MASTER, "json_command", return_value={"result": {"pane": {"pane_id": "created-child"}}}),
            patch.object(MASTER, "invoke", side_effect=MASTER.MasterError("rename failed")),
            redirect_stderr(output),
        ):
            result = MASTER.main()
        self.assertEqual(result, 2)
        self.assertIn("created pane created-child remains open", output.getvalue())


if __name__ == "__main__":
    unittest.main()

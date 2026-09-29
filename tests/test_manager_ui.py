"""WProxy Manager server-list viewport regression checks."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "manager/wproxy-manager.py"


class ManagerUIContractTests(unittest.TestCase):
    def test_four_rows_bound_the_viewport_not_the_data(self):
        source = SOURCE.read_text()
        self.assertIn("VISIBLE_NODE_ROWS = 4", source)
        self.assertIn("for n in nodes:", source)
        self.assertNotIn("for n in nodes[:", source)
        self.assertNotIn("nodes = nodes[:", source)
        self.assertIn("heights[:VISIBLE_NODE_ROWS]", source)

    def test_node_list_has_its_own_scroll_view(self):
        source = SOURCE.read_text()
        self.assertIn("self.nodes_scroller = Gtk.ScrolledWindow()", source)
        self.assertIn("self.nodes_scroller.set_child(self.nodes_box)", source)
        self.assertIn("self.nodes_scroller.set_valign(Gtk.Align.START)", source)
        self.assertIn(
            "Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC", source
        )


if __name__ == "__main__":
    unittest.main()

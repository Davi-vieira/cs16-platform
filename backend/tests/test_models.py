import unittest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from app.models.models import Player


class TestPlayerModels(unittest.TestCase):
    def test_player_rank_progression(self):
        p1 = Player(display_name="Recruta", level=1)
        self.assertEqual(p1.rank, "Iniciante")

        p9 = Player(display_name="Quase Lá", level=9)
        self.assertEqual(p9.rank, "Iniciante")

        p10 = Player(display_name="Amador 1", level=10)
        self.assertEqual(p10.rank, "Amador")

        p24 = Player(display_name="Amador Top", level=24)
        self.assertEqual(p24.rank, "Amador")

        p25 = Player(display_name="Competente 1", level=25)
        self.assertEqual(p25.rank, "Competente")

        p49 = Player(display_name="Competente Top", level=49)
        self.assertEqual(p49.rank, "Competente")

        p50 = Player(display_name="Veterano 1", level=50)
        self.assertEqual(p50.rank, "Veterano")

        p74 = Player(display_name="Veterano Top", level=74)
        self.assertEqual(p74.rank, "Veterano")

        p75 = Player(display_name="Elite 1", level=75)
        self.assertEqual(p75.rank, "Elite")

        p100 = Player(display_name="Lenda", level=100)
        self.assertEqual(p100.rank, "Elite")


if __name__ == "__main__":
    unittest.main()

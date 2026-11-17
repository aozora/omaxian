"""The command line as an agent uses it: the built binary, no display."""

import json
import os
import subprocess
import tempfile
import unittest

OMAVIEW = os.environ.get("OMAVIEW", "build/omaview")


def run(*arguments, home):
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in ("WAYLAND_DISPLAY", "DISPLAY", "QT_QPA_PLATFORM")
    }
    environment.update(HOME=home, XDG_STATE_HOME=os.path.join(home, "state"), LANG="da_DK.UTF-8")
    return subprocess.run([OMAVIEW, *arguments], capture_output=True, text=True, env=environment, timeout=120)


class CommandLineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.home = cls.directory.name
        cls.clip = os.path.join(cls.home, "clip.mkv")
        with open(os.path.join(cls.home, "chapters.txt"), "w") as chapters:
            chapters.write(";FFMETADATA1\ntitle=Test Clip\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1500\n"
                           "title=First\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=1500\nEND=3000\ntitle=Second\n")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=25:duration=3",
                        "-f", "lavfi", "-i", "sine=duration=3", "-i", os.path.join(cls.home, "chapters.txt"),
                        "-map", "0:v", "-map", "1:a", "-map_metadata", "2", "-map_chapters", "2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-metadata:s:a:0", "language=eng",
                        cls.clip], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_help_needs_no_display(self):
        result = run("--help", home=self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("info <file>", result.stdout)

    def test_info_as_json(self):
        result = run("info", self.clip, "--json", home=self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        info = json.loads(result.stdout)
        self.assertAlmostEqual(info["duration"], 3.0, delta=0.1)
        self.assertEqual(info["title"], "Test Clip")
        self.assertEqual([s["type"] for s in info["streams"]], ["video", "audio"])
        self.assertEqual(info["streams"][0]["width"], 320)
        self.assertEqual(info["streams"][1]["language"], "eng")
        self.assertEqual([c["title"] for c in info["chapters"]], ["First", "Second"])
        self.assertIsNone(info["resume"])

    def test_info_as_text(self):
        result = run("info", self.clip, home=self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Chapter   0:00:01.500  Second", result.stdout)

    def test_frame(self):
        out = os.path.join(self.home, "still.png")
        result = run("frame", self.clip, "--at", "0:01.5", "-o", out, "--json", home=self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        answer = json.loads(result.stdout)
        self.assertEqual((answer["width"], answer["height"]), (320, 180))
        self.assertEqual(answer["at"], 1.5)
        with open(out, "rb") as png:
            self.assertEqual(png.read(8), b"\x89PNG\r\n\x1a\n")

    def test_info_of_a_picture(self):
        picture = os.path.join(self.home, "still.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=64x48", "-frames:v", "1",
                        picture], check=True)
        result = run("info", picture, "--json", home=self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        info = json.loads(result.stdout)
        self.assertEqual((info["type"], info["format"], info["width"], info["height"]), ("picture", "PNG", 64, 48))
        self.assertFalse(info["animated"])
        result = run("info", picture, home=self.home)
        self.assertIn("Size      64x48", result.stdout)
        # A picture has no frames to take.
        result = run("frame", picture, "-o", os.path.join(self.home, "x.png"), home=self.home)
        self.assertEqual(result.returncode, 1)
        self.assertIn("is a picture", result.stderr)

    def test_errors_go_to_stderr_in_english(self):
        result = run("info", os.path.join(self.home, "missing.mkv"), home=self.home)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("No such file", result.stderr)
        result = run("frame", self.clip, "--at", "soon", "-o", "x.png", home=self.home)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Not a time", result.stderr)
        result = run("frame", self.clip, home=self.home)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Usage", result.stderr)

    def test_skill_installs_and_links(self):
        os.makedirs(os.path.join(self.home, ".claude"), exist_ok=True)
        result = run("skill", "install", home=self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        skill = os.path.join(self.home, ".agents/skills/omaview/SKILL.md")
        with open(skill) as text:
            self.assertIn("name: omaview", text.read())
        link = os.path.join(self.home, ".claude/skills/omaview")
        self.assertTrue(os.path.islink(link))
        self.assertEqual(os.readlink(link), "../../.agents/skills/omaview")
        printed = run("skill", home=self.home)
        self.assertIn("omaview frame", printed.stdout)


if __name__ == "__main__":
    unittest.main()

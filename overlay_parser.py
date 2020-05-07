import io
import re

class OverlayParser:
    def __init__(self, overlay):
        self.overlay = overlay

    def extract_comment(self):
        with io.open(self.overlay, "r") as f:
            file_content = f.read()
            self.comments = re.sub(r'// *([^\n]*\n)|/\*(.*)\*/|[^\n]*\n', r'\1\2', file_content, flags=re.DOTALL)

    def parse(self):
        self.extract_comment()
        # Remove SPDX License Identifier
        comments = re.sub(r'SPDX-License-Identifier: ([^\n]*)\n', '', self.comments, flags=re.DOTALL)
        self.description = comments.split("\n")[0]


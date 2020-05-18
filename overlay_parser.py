import io
import re

class OverlayParser:
    def __init__(self, overlay):
        self.overlay = overlay
        self.compat_path = "/sys/firmware/devicetree/base/compatible"
        self.counter = 0
        self.description = ""

    def extract_comments(self):
        with io.open(self.overlay, "r") as f:
            file_content = f.read()
            comments = re.sub(r'// *([^\n]*\n)|/\*(.*)\*/|[^\n]*\n', r'\1\2',
                              file_content, flags=re.DOTALL)

        return comments

    def parse(self):
        comments = self.extract_comments()
        # Remove SPDX License Identifier
        comments = re.sub(r'SPDX-License-Identifier: ([^\n]*)\n', '', comments,
                          flags=re.DOTALL)
        self.description = comments.split("\n")[0]

    def block_repl(self, matchobj):
        text = matchobj.group(0)
        if "{" in text:
            self.counter += 1

        if self.counter > 0:
            ret = None
        else:
            ret = text

        if "}" in text:
            self.counter -= 1

        return ret

    def _get_overlay_compatibilities(self, overlay):
        with io.open(overlay, "r") as f:
            overlay_content = f.read()

        # Search for the main part \{ ... };
        main_content = re.sub(r'.*/ {(.*)} *;', r'\1', overlay_content, flags=re.DOTALL)
        # Remove all innter nodes we only want the root properties
        outer_block = re.sub(r'.*?[{;]', self.block_repl, main_content, flags=re.DOTALL)
        # Get the compatibility props
        compatible = re.sub(r'.*?compatible *= *(.*?);', r'\1,', outer_block, flags=re.DOTALL)
        compatible = re.sub(r'[\n\r]', '', compatible)

        #compatible_list = re.split(r'" *, *"?', compatible)
        compatibility_list = re.findall(r'.*?"(.*?)" *, *', compatible)
        return compatibility_list

    def check_compatibility(self):
        with io.open(self.compat_path, "r") as f:
            compatibilities = f.read()

        compatibilities = compatibilities.split("\0")

        overlay_compatibilities = self._get_overlay_compatibilities(self.overlay)

        for compatibility in compatibilities:
            for overlay_compatibility in overlay_compatibilities:
                # If there is a match
                if overlay_compatibility == compatibility:
                    return True

        return False

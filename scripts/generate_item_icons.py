#!/usr/bin/env python3
"""Paint unique 32x32 icons from each item display name.

Kept as the entry point the docs name. Implementation lives in paint_item_icons.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from paint_item_icons import main

if __name__ == '__main__':
    main()

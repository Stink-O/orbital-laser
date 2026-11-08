#!/usr/bin/env python3
"""mkpage.py PAGE_DIR: joins the template, the sweeps and content.py's prose into PAGE_DIR/index.html"""
import sys,json,pathlib,importlib.util
sys.path.insert(0,__file__.rsplit('/',1)[0])
here=pathlib.Path(__file__).parent
out=pathlib.Path(sys.argv[1])
spec=importlib.util.spec_from_file_location('content',sys.argv[2]); c=importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
t=(here/'page.html').read_text()
t=t.replace('BODY_INTRO',c.INTRO).replace('CAM_NOTE',c.CAMNOTE).replace('DATA_JSON',json.dumps(c.data(out),separators=(',',':')))
(out/'index.html').write_text(t); print((out/'index.html').stat().st_size)

#!/bin/bash
set -euxo pipefail
cd -- "$( dirname -- "${BASH_SOURCE[0]}" )"
# https://www.w3.org/TR/xhtml1/dtds.html
# https://www.w3.org/TR/xhtml1-schema/
wget -nv -N -i- <<'EOF'
https://www.w3.org/2001/xml.xsd
https://www.w3.org/2002/08/xhtml/xhtml1-strict.xsd
https://www.w3.org/2002/08/xhtml/xhtml1-transitional.xsd
https://www.w3.org/2002/08/xhtml/xhtml1-frameset.xsd
https://www.w3.org/TR/xhtml1/DTD/xhtml1.dcl
https://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd
https://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd
https://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd
https://www.w3.org/TR/xhtml1/DTD/xhtml-lat1.ent
https://www.w3.org/TR/xhtml1/DTD/xhtml.soc
https://www.w3.org/TR/xhtml1/DTD/xhtml-special.ent
https://www.w3.org/TR/xhtml1/DTD/xhtml-symbol.ent
EOF
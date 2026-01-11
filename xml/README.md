
These XML files are the nodes scraped from PerlMonks, with some changes applied:
- Encoding converted to UTF-8
- The `<doctext>` may have been patched
- Nodes that are parts of threads have `<thread>` elements added
- Nodes have a `_doctext_mode` attribute added

*Note* there are also a couple of HTML files,
mostly of those nodes that don't include a `<doctext>`.

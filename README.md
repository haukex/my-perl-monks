My PerlMonks Contributions
==========================

**<https://haukex.github.io/my-perl-monks>**

Main code in this repo:
1. `scraper.pl` scrapes all the desired nodes into the `xml` folder, using request caching.
   - ⚠️ **Warning:** Your login cookie will be persisted in the cache;
     do not share your cache folder!
   - Note the scraping for my user has already happened and the results are in this repo.
   - When starting from scratch, the scraper may need to be run twice, because it may need
     the `node_info.xml` that it itself builds.
2. `generator.pl` takes all the scraped XML files and generates the HTML output.
3. `search.sh` then builds the static search functionality.

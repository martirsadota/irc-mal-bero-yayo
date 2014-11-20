irc-mal-bero-yayo
=================

IRC infobot that uses [MyAnimeList](http://myanimelist.net) info

Visit the live instance at [#doki on Rizon](irc://irc.rizon.net/doki).

## Features currently available
  * General search
   * Anime
   * Manga
   * Characters
   * People
   * Users
     * Anime Stats
     * Manga Stats
  * [VNDB](http://vndb.org) Search
    * Visual Novels
    * Characters
  * The `!whodid` trigger (which fansub group/s did a particular show)
  * Google Search Fallback (lovingly called `Wilbell`, because it's **magical!**)
   
    ```perl
    sub Wilbell {
    # Wilbell
    # (Magical!) Google Search Fallback
    ...
    }
    ```
    
## In the pipeline
  * `.lw` (User's last watched anime)

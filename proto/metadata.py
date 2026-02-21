import os
import hashlib
import requests
import json
from mutagen import File
from mutagen.id3 import ID3, APIC, USLT, TIT2, TPE1, TALB
from mutagen.mp3 import MP3
from mutagen.flac import FLAC, Picture
from mutagen.mp4 import MP4, MP4Cover
from mutagen.dsf import DSF
from PIL import Image
from io import BytesIO

class MetadataManager:
    def __init__(self, cache_dir="cache"):
        self.cache_dir = cache_dir
        self.img_cache_dir = os.path.join(cache_dir, "images")
        self.lyric_cache_dir = os.path.join(cache_dir, "lyrics")
        
        if not os.path.exists(self.img_cache_dir):
            os.makedirs(self.img_cache_dir)
        if not os.path.exists(self.lyric_cache_dir):
            os.makedirs(self.lyric_cache_dir)

    def _normalize_text(self, s):
        if s is None:
            return None
        if isinstance(s, bytes):
            for enc in ("utf-8", "gbk", "latin-1"):
                try:
                    return s.decode(enc)
                except:
                    pass
            return s.decode("utf-8", errors="replace")
        if isinstance(s, str):
            def cjk_count(x):
                return sum(1 for ch in x if '\u4e00' <= ch <= '\u9fff')
            candidates = [s]
            try:
                candidates.append(s.encode("latin-1").decode("utf-8", errors="replace"))
            except:
                pass
            try:
                candidates.append(s.encode("latin-1").decode("gbk", errors="replace"))
            except:
                pass
            best = max(candidates, key=lambda x: (cjk_count(x), -x.count('\ufffd')))
            return best
        return str(s)

    def get_metadata(self, file_path, fetch_network=True):
        """
        Get metadata for a file.
        Returns a dict: {
            'title': str,
            'artist': str,
            'album': str,
            'cover_path': str (path to local image file) or None,
            'lyrics': str or None
        }
        """
        meta = self._extract_tags(file_path)
        
        # If title/artist missing, use filename
        if not meta['title']:
            meta['title'] = os.path.splitext(os.path.basename(file_path))[0]
        if not meta['artist']:
            meta['artist'] = "Unknown Artist"

        # Unique ID for caching
        cache_id = self._get_cache_id(meta['artist'], meta['title'])
        
        # Handle Cover Art
        if meta['cover_data']:
            # Save embedded cover to cache if not already there
            cover_path = os.path.join(self.img_cache_dir, f"{cache_id}_embedded.jpg")
            if not os.path.exists(cover_path):
                try:
                    with open(cover_path, "wb") as f:
                        f.write(meta['cover_data'])
                except Exception as e:
                    print(f"Error saving embedded cover: {e}")
            meta['cover_path'] = cover_path
        else:
            # Check cache for online cover
            cover_path = os.path.join(self.img_cache_dir, f"{cache_id}_online.jpg")
            if os.path.exists(cover_path):
                meta['cover_path'] = cover_path
            elif fetch_network:
                # Fetch online
                meta['cover_path'] = self._fetch_online_cover(meta['title'], meta['artist'], cache_id)

        # Handle Lyrics
        if not meta['lyrics']:
             # Check cache
            lyric_path = os.path.join(self.lyric_cache_dir, f"{cache_id}.txt")
            if os.path.exists(lyric_path):
                with open(lyric_path, "r", encoding="utf-8") as f:
                    meta['lyrics'] = f.read()
            elif fetch_network:
                # Fetch online
                meta['lyrics'] = self._fetch_online_lyrics(meta['title'], meta['artist'], cache_id)

        return meta

    def _extract_tags(self, file_path):
        meta = {
            'title': None,
            'artist': None,
            'album': None,
            'cover_data': None,
            'lyrics': None
        }
        
        try:
            audio = File(file_path)
            if not audio:
                return meta

            # MP3
            if isinstance(audio, MP3) or isinstance(audio, ID3):
                # Ensure ID3 tags exist
                if audio.tags is None:
                    try:
                        audio.add_tags()
                    except:
                        pass
                
                tags = audio.tags
                if tags:
                    tit2 = tags.get("TIT2")
                    tpe1 = tags.get("TPE1")
                    talb = tags.get("TALB")
                    meta['title'] = self._normalize_text((tit2.text[0] if getattr(tit2, "text", None) else str(tit2)) if tit2 else None)
                    meta['artist'] = self._normalize_text((tpe1.text[0] if getattr(tpe1, "text", None) else str(tpe1)) if tpe1 else None)
                    meta['album'] = self._normalize_text((talb.text[0] if getattr(talb, "text", None) else str(talb)) if talb else None)
                    
                    # Cover
                    for key in tags.keys():
                        if key.startswith("APIC:"):
                            meta['cover_data'] = tags[key].data
                            break
                    
                    # Lyrics
                    for key in tags.keys():
                        if key.startswith("USLT:"):
                            meta['lyrics'] = str(tags[key])
                            break
            
            # FLAC
            elif isinstance(audio, FLAC):
                if audio.tags:
                    meta['title'] = self._normalize_text(audio.tags.get("title", [None])[0])
                    meta['artist'] = self._normalize_text(audio.tags.get("artist", [None])[0])
                    meta['album'] = self._normalize_text(audio.tags.get("album", [None])[0])
                    meta['lyrics'] = audio.tags.get("lyrics", [None])[0]
                
                if audio.pictures:
                    meta['cover_data'] = audio.pictures[0].data

            # M4A / MP4
            elif isinstance(audio, MP4):
                if audio.tags:
                    meta['title'] = self._normalize_text(audio.tags.get("\xa9nam", [None])[0])
                    meta['artist'] = self._normalize_text(audio.tags.get("\xa9ART", [None])[0])
                    meta['album'] = self._normalize_text(audio.tags.get("\xa9alb", [None])[0])
                    meta['lyrics'] = audio.tags.get("\xa9lyr", [None])[0]
                    
                    covers = audio.tags.get("covr", [])
                    if covers:
                        meta['cover_data'] = covers[0]

            # DSF
            elif isinstance(audio, DSF):
                if audio.tags is None:
                    try:
                        audio.add_tags()
                    except:
                        pass
                
                tags = audio.tags
                if tags:
                    tit2 = tags.get("TIT2")
                    tpe1 = tags.get("TPE1")
                    talb = tags.get("TALB")
                    meta['title'] = self._normalize_text((tit2.text[0] if getattr(tit2, "text", None) else str(tit2)) if tit2 else None)
                    meta['artist'] = self._normalize_text((tpe1.text[0] if getattr(tpe1, "text", None) else str(tpe1)) if tpe1 else None)
                    meta['album'] = self._normalize_text((talb.text[0] if getattr(talb, "text", None) else str(talb)) if talb else None)
                    
                    # Cover
                    for key in tags.keys():
                        if key.startswith("APIC:"):
                            meta['cover_data'] = tags[key].data
                            break
                    
                    # Lyrics
                    for key in tags.keys():
                        if key.startswith("USLT:"):
                            meta['lyrics'] = str(tags[key])
                            break

        except Exception as e:
            print(f"Error extracting tags from {file_path}: {e}")

        return meta

    def _get_cache_id(self, artist, title):
        # Normalize strings for better caching
        s = f"{artist or ''}-{title or ''}".lower().encode('utf-8')
        return hashlib.md5(s).hexdigest()

    def _fetch_online_cover(self, title, artist, cache_id):
        # Using iTunes Search API
        try:
            term = f"{title} {artist}"
            url = "https://itunes.apple.com/search"
            params = {
                "term": term,
                "media": "music",
                "entity": "song",
                "limit": 1
            }
            response = requests.get(url, params=params, timeout=5)
            if response.status_code == 200:
                data = response.json()
                if data["resultCount"] > 0:
                    artwork_url = data["results"][0].get("artworkUrl100")
                    if artwork_url:
                        # Get higher res
                        artwork_url = artwork_url.replace("100x100", "600x600")
                        img_resp = requests.get(artwork_url, timeout=5)
                        if img_resp.status_code == 200:
                            save_path = os.path.join(self.img_cache_dir, f"{cache_id}_online.jpg")
                            with open(save_path, "wb") as f:
                                f.write(img_resp.content)
                            return save_path
        except Exception as e:
            print(f"Error fetching online cover: {e}")
        return None

    def _fetch_online_lyrics(self, title, artist, cache_id):
        # Try 1: Netease Cloud Music (Unofficial) - Better for domestic network
        lyrics = self._fetch_netease_lyrics(title, artist)
        if lyrics:
            self._save_lyrics(lyrics, cache_id)
            return lyrics

        # Try 2: lrclib.net API
        lyrics = self._fetch_lrclib_lyrics(title, artist)
        if lyrics:
            self._save_lyrics(lyrics, cache_id)
            return lyrics
            
        return None

    def _save_lyrics(self, lyrics, cache_id):
        try:
            save_path = os.path.join(self.lyric_cache_dir, f"{cache_id}.txt")
            with open(save_path, "w", encoding="utf-8") as f:
                f.write(lyrics)
        except Exception as e:
            print(f"Error saving lyrics: {e}")

    def _fetch_lrclib_lyrics(self, title, artist):
        try:
            url = "https://lrclib.net/api/get"
            params = {
                "artist_name": artist,
                "track_name": title
            }
            response = requests.get(url, params=params, timeout=5)
            if response.status_code == 200:
                data = response.json()
                return data.get("syncedLyrics") or data.get("plainLyrics")
        except Exception as e:
            print(f"Error fetching from lrclib: {e}")
        return None

    def _fetch_netease_lyrics(self, title, artist):
        try:
            # 1. Search
            search_url = "http://music.163.com/api/search/get/web"
            headers = {
                "Referer": "http://music.163.com/",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
            }
            params = {
                "s": f"{title} {artist}",
                "type": 1,
                "offset": 0,
                "total": "true",
                "limit": 1
            }
            response = requests.post(search_url, headers=headers, params=params, timeout=5)
            if response.status_code != 200:
                return None
                
            data = response.json()
            songs = data.get("result", {}).get("songs", [])
            if not songs:
                return None

            song_id = songs[0]["id"]

            # 2. Get Lyrics
            lyric_url = f"http://music.163.com/api/song/lyric?os=pc&id={song_id}&lv=-1&kv=-1&tv=-1"
            lyric_resp = requests.get(lyric_url, headers=headers, timeout=5)
            if lyric_resp.status_code == 200:
                lyric_data = lyric_resp.json()
                return lyric_data.get("lrc", {}).get("lyric")
        except Exception as e:
            print(f"Error fetching from Netease: {e}")
        return None

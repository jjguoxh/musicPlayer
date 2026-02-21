import requests
import json

def test_lrclib(artist, title):
    print(f"Testing lrclib.net for {artist} - {title}...")
    url = "https://lrclib.net/api/get"
    params = {
        "artist_name": artist,
        "track_name": title
    }
    try:
        response = requests.get(url, params=params, timeout=10)
        print(f"Status Code: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            # print(json.dumps(data, indent=2, ensure_ascii=False))
            lyrics = data.get("syncedLyrics") or data.get("plainLyrics")
            if lyrics:
                print("Lyrics found!")
                print(lyrics[:100] + "...")
            else:
                print("No lyrics found in response.")
        else:
            print("Request failed.")
            print(response.text)
    except Exception as e:
        print(f"Error: {e}")
    print("-" * 30)

def test_netease(artist, title):
    print(f"Testing Netease (Unofficial) for {artist} - {title}...")
    # 1. Search for the song ID
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
        "limit": 5
    }
    
    try:
        response = requests.post(search_url, headers=headers, params=params, timeout=10)
        if response.status_code == 200:
            data = response.json()
            songs = data.get("result", {}).get("songs", [])
            if not songs:
                print("No songs found.")
                return

            song_id = songs[0]["id"]
            song_name = songs[0]["name"]
            song_artist = songs[0]["artists"][0]["name"]
            print(f"Found song: {song_name} by {song_artist} (ID: {song_id})")

            # 2. Get lyrics using song ID
            lyric_url = f"http://music.163.com/api/song/lyric?os=pc&id={song_id}&lv=-1&kv=-1&tv=-1"
            lyric_resp = requests.get(lyric_url, headers=headers, timeout=10)
            if lyric_resp.status_code == 200:
                lyric_data = lyric_resp.json()
                lrc = lyric_data.get("lrc", {}).get("lyric")
                if lrc:
                    print("Lyrics found!")
                    print(lrc[:100] + "...")
                else:
                    print("No lyrics in lyric response.")
            else:
                print("Failed to fetch lyrics.")
        else:
            print("Search failed.")
    except Exception as e:
        print(f"Error: {e}")
    print("-" * 30)

if __name__ == "__main__":
    test_lrclib("谭咏麟", "谁可改变")
    test_netease("谭咏麟", "谁可改变")

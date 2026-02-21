import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import os
import time
import threading
import re
import json
from PIL import Image, ImageTk
from player import MusicPlayer
from metadata import MetadataManager
from mutagen import File

class MusicPlayerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Python 音乐播放器")
        self.root.geometry("900x600")

        self.player = MusicPlayer()
        self.metadata_manager = MetadataManager()
        self.playlist = []
        self.current_index = -1
        self.current_duration = 0
        self.parsed_lyrics = []  # List of (timestamp, line_text)
        self.active_lyric_index = -1
        self.is_seeking = False  # Flag to prevent update loop from fighting with user dragging
        
        # UI Elements
        self.cover_label = None
        self.title_label = None
        self.artist_label = None
        self.lyrics_text = None
        self.default_cover = None
        
        self.create_widgets()
        
        # Load default cover placeholder (optional, or just use blank)
        self.create_default_cover()

        # Update progress loop
        self.root.after(200, self.update_status)
        
        # Load saved playlist state
        self.load_playlist_state()

    def create_default_cover(self):
        # Create a simple gray placeholder
        img = Image.new('RGB', (200, 200), color = (73, 109, 137))
        self.default_cover = ImageTk.PhotoImage(img)
        if self.cover_label:
            self.cover_label.config(image=self.default_cover)

    def create_widgets(self):
        # Main container with PanedWindow for resizable split
        main_pane = tk.PanedWindow(self.root, orient=tk.HORIZONTAL)
        main_pane.pack(fill=tk.BOTH, expand=True)

        # --- LEFT PANEL (Playlist) ---
        left_frame = ttk.Frame(main_pane, padding="5")
        main_pane.add(left_frame, minsize=200)

        # Playlist Label
        ttk.Label(left_frame, text="播放列表", font=('Arial', 12, 'bold')).pack(pady=5)

        # Listbox with scrollbar
        list_frame = ttk.Frame(left_frame)
        list_frame.pack(fill=tk.BOTH, expand=True)
        
        self.playlist_box = tk.Listbox(list_frame, selectmode=tk.SINGLE)
        self.playlist_box.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.playlist_box.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.playlist_box.config(yscrollcommand=scrollbar.set)
        self.playlist_box.bind('<Double-1>', self.play_selected)

        # Playlist Controls
        playlist_controls = ttk.Frame(left_frame, padding="5")
        playlist_controls.pack(fill=tk.X)
        ttk.Button(playlist_controls, text="+ 添加", command=self.add_files, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(playlist_controls, text="+ 目录", command=self.add_directory, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(playlist_controls, text="- 删除", command=self.remove_file, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(playlist_controls, text="清空", command=self.clear_playlist, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(playlist_controls, text="从磁盘删除", command=self.delete_selected_from_disk, width=10).pack(side=tk.LEFT, padx=2)

        # --- RIGHT PANEL (Metadata + Controls) ---
        right_frame = ttk.Frame(main_pane, padding="10")
        main_pane.add(right_frame, minsize=400)

        # Top: Cover Art and Info (Pack FIRST)
        top_info_frame = ttk.Frame(right_frame)
        top_info_frame.pack(side=tk.TOP, fill=tk.X, pady=10)

        # Cover Image
        self.cover_label = ttk.Label(top_info_frame, text="无封面")
        self.cover_label.pack(side=tk.LEFT, padx=10)
        self.id3_btn = ttk.Button(top_info_frame, text="查看ID3", command=self.show_id3_window)
        self.id3_btn.place(in_=self.cover_label, relx=1.0, x=-8, y=8, anchor='ne')

        # Info Labels
        info_text_frame = ttk.Frame(top_info_frame)
        info_text_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=10)
        
        self.title_label = ttk.Label(info_text_frame, text="暂无播放", font=('Arial', 16, 'bold'))
        self.title_label.pack(anchor='w')
        
        self.artist_label = ttk.Label(info_text_frame, text="未知艺术家", font=('Arial', 12))
        self.artist_label.pack(anchor='w')
        
        self.album_label = ttk.Label(info_text_frame, text="", font=('Arial', 10, 'italic'))
        self.album_label.pack(anchor='w')

        # Bottom: Playback Controls (Pack SECOND, side=BOTTOM)
        # This ensures controls are always visible at the bottom regardless of window height
        controls_container = ttk.Frame(right_frame)
        controls_container.pack(side=tk.BOTTOM, fill=tk.X, pady=5)

        # Status and Time
        status_frame = ttk.Frame(controls_container)
        status_frame.pack(fill=tk.X, pady=2)
        
        self.status_var = tk.StringVar(value="就绪")
        self.status_label = ttk.Label(status_frame, textvariable=self.status_var, font=('Arial', 9))
        self.status_label.pack(side=tk.LEFT)
        
        self.time_var = tk.StringVar(value="00:00 / 00:00")
        self.time_label = ttk.Label(status_frame, textvariable=self.time_var, font=('Arial', 9))
        self.time_label.pack(side=tk.RIGHT)

        # Progress Bar
        self.progress_var = tk.DoubleVar()
        self.progress_scale = ttk.Scale(controls_container, from_=0, to=100, orient=tk.HORIZONTAL, variable=self.progress_var, command=self.on_seek_drag)
        self.progress_scale.pack(fill=tk.X, pady=5)
        self.progress_scale.bind("<ButtonRelease-1>", self.on_seek_release)
        self.progress_scale.bind("<ButtonPress-1>", self.on_seek_press)

        # Buttons and Volume
        btns_frame = ttk.Frame(controls_container)
        btns_frame.pack(fill=tk.X, pady=5)

        # Use Grid for better adaptive layout of buttons
        btns_frame.columnconfigure(0, weight=1) # Spacer Left
        btns_frame.columnconfigure(6, weight=1) # Spacer Right (before volume)

        # Playback Buttons (Centered)
        ttk.Button(btns_frame, text="⏮ 上一首", command=self.prev_song, width=8).grid(row=0, column=1, padx=5)
        self.play_btn = ttk.Button(btns_frame, text="▶ 播放", command=self.toggle_play, width=8)
        self.play_btn.grid(row=0, column=2, padx=5)
        ttk.Button(btns_frame, text="⏹ 停止", command=self.stop_song, width=8).grid(row=0, column=3, padx=5)
        ttk.Button(btns_frame, text="⏭ 下一首", command=self.next_song, width=8).grid(row=0, column=4, padx=5)

        # Volume (Right Aligned)
        vol_frame = ttk.Frame(btns_frame)
        vol_frame.grid(row=0, column=7, sticky='e')
        
        ttk.Label(vol_frame, text="音量:").pack(side=tk.LEFT)
        self.vol_scale = ttk.Scale(vol_frame, from_=0, to=100, orient=tk.HORIZONTAL, command=self.set_volume)
        self.vol_scale.set(50)
        self.vol_scale.pack(side=tk.LEFT, padx=5)

        # Middle: Lyrics (Pack LAST, fill=BOTH, expand=True)
        # This takes up all remaining space between Top Info and Bottom Controls
        lyrics_frame = ttk.LabelFrame(right_frame, text="歌词")
        lyrics_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=10)
        
        self.lyrics_text = tk.Text(lyrics_frame, wrap=tk.WORD, font=('Segoe UI', 10), state=tk.DISABLED, bg="#f0f0f0")
        lyrics_scroll = ttk.Scrollbar(lyrics_frame, command=self.lyrics_text.yview)
        self.lyrics_text.config(yscrollcommand=lyrics_scroll.set)
        
        # Tag for current lyric line
        self.lyrics_text.tag_config("current_line", foreground="#ff4400", font=('Segoe UI', 12, 'bold'))
        self.lyrics_text.tag_config("center", justify='center')
        
        self.lyrics_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        lyrics_scroll.pack(side=tk.RIGHT, fill=tk.Y)

    def save_playlist_state(self):
        """Save current playlist and index to JSON file."""
        state = {
            'playlist': self.playlist,
            'current_index': self.current_index
        }
        try:
            with open('playlist.json', 'w', encoding='utf-8') as f:
                json.dump(state, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Failed to save playlist state: {e}")

    def load_playlist_state(self):
        """Load playlist and index from JSON file."""
        if not os.path.exists('playlist.json'):
            return
            
        try:
            with open('playlist.json', 'r', encoding='utf-8') as f:
                state = json.load(f)
                
            playlist_files = state.get('playlist', [])
            saved_index = state.get('current_index', -1)
            
            # Verify files exist before adding
            valid_files = []
            for file_path in playlist_files:
                if os.path.exists(file_path):
                    valid_files.append(file_path)
            
            if valid_files:
                self.playlist = valid_files
                for file in self.playlist:
                    self.playlist_box.insert(tk.END, os.path.basename(file))
                
                # Restore selection if valid
                if 0 <= saved_index < len(self.playlist):
                    self.current_index = saved_index
                    self.playlist_box.selection_set(saved_index)
                    self.playlist_box.activate(saved_index)
                    # Optional: Auto-load metadata for the last played song without playing
                    # self.load_metadata_basic(self.playlist[saved_index])
                    
        except Exception as e:
            print(f"Failed to load playlist state: {e}")

    def add_files(self):
        file_types = [
            ("音频文件", "*.mp3 *.flac *.m4a *.wav *.ogg *.dsf"),
            ("所有文件", "*.*")
        ]
        files = filedialog.askopenfilenames(filetypes=file_types)
        for file in files:
            self.playlist.append(file)
            self.playlist_box.insert(tk.END, os.path.basename(file))
        self.save_playlist_state()

    def add_directory(self):
        directory = filedialog.askdirectory()
        if directory:
            supported_extensions = ('.mp3', '.flac', '.m4a', '.wav', '.ogg', '.dsf')
            added_count = 0
            for root, dirs, files in os.walk(directory):
                for file in files:
                    if file.lower().endswith(supported_extensions):
                        full_path = os.path.join(root, file)
                        # Avoid duplicates (optional check, can be slow for large lists but good for UX)
                        if full_path not in self.playlist:
                            self.playlist.append(full_path)
                            self.playlist_box.insert(tk.END, file)
                            added_count += 1
            
            if added_count > 0:
                self.save_playlist_state()
                messagebox.showinfo("成功", f"从目录添加了 {added_count} 首歌曲。")
            else:
                messagebox.showinfo("提示", "所选目录中未找到支持的音乐文件。")

    def remove_file(self):
        selection = self.playlist_box.curselection()
        if selection:
            index = selection[0]
            self.playlist_box.delete(index)
            self.playlist.pop(index)
            if index < self.current_index:
                self.current_index -= 1
            elif index == self.current_index:
                self.stop_song()
                self.current_index = -1
            self.save_playlist_state()

    def delete_selected_from_disk(self):
        selection = self.playlist_box.curselection()
        if not selection:
            messagebox.showinfo("提示", "请先选择要删除的歌曲。")
            return
        index = selection[0]
        file_path = self.playlist[index]
        playing_current = (index == self.current_index)
        if playing_current:
            self.player.stop()
        try:
            if os.path.exists(file_path):
                os.remove(file_path)
        except Exception as e:
            messagebox.showerror("错误", f"删除失败:\n{e}")
            return
        self.playlist_box.delete(index)
        self.playlist.pop(index)
        if index < self.current_index:
            self.current_index -= 1
        elif playing_current:
            if self.playlist:
                next_idx = index if index < len(self.playlist) else 0
                self.play_index(next_idx)
            else:
                self.current_index = -1
                self.stop_song()
        self.save_playlist_state()
    def clear_playlist(self):
        self.stop_song()
        self.playlist = []
        self.playlist_box.delete(0, tk.END)
        self.current_index = -1
        self.save_playlist_state()

    def play_selected(self, event=None):
        selection = self.playlist_box.curselection()
        if selection:
            index = selection[0]
            self.play_index(index)

    def play_index(self, index):
        if 0 <= index < len(self.playlist):
            self.current_index = index
            self.save_playlist_state()  # Save current playing index
            file_path = self.playlist[index]
            
            try:
                duration = self.player.load_file(file_path)
                self.current_duration = duration if duration else 0
                
                self.player.play()
                self.play_btn.config(text="⏸ 暂停")
                self.status_var.set(f"正在播放")
                
                # Highlight in listbox
                self.playlist_box.selection_clear(0, tk.END)
                self.playlist_box.selection_set(index)
                self.playlist_box.activate(index)
                
                # Reset metadata UI temporarily
                self.title_label.config(text=os.path.basename(file_path))
                self.artist_label.config(text="加载信息中...")
                self.album_label.config(text="")
                self.cover_label.config(image=self.default_cover)
                self.lyrics_text.config(state=tk.NORMAL)
                self.lyrics_text.delete(1.0, tk.END)
                self.lyrics_text.insert(tk.END, "加载歌词中...")
                self.lyrics_text.config(state=tk.DISABLED)
                
                self.parsed_lyrics = []
                self.active_lyric_index = -1
                
                # First load basic metadata (local file only) to show something immediately
                self.load_metadata_basic(file_path)

                # Start thread to fetch advanced metadata (network)
                threading.Thread(target=self.load_metadata_network, args=(file_path,), daemon=True).start()
                
            except Exception as e:
                messagebox.showerror("错误", f"无法播放文件:\n{os.path.basename(file_path)}\n\n错误: {str(e)}")

    def load_metadata_basic(self, file_path):
        # Load without network first
        meta = self.metadata_manager.get_metadata(file_path, fetch_network=False)
        self.update_metadata_ui(meta)

    def load_metadata_network(self, file_path):
        # This will be slow but it runs in a thread
        meta = self.metadata_manager.get_metadata(file_path, fetch_network=True)
        # Update UI in main thread
        self.root.after(0, self.update_metadata_ui, meta)

    def update_metadata_ui(self, meta):
        # Update Labels
        self.title_label.config(text=meta.get('title', '未知标题'))
        self.artist_label.config(text=meta.get('artist', '未知艺术家'))
        self.album_label.config(text=meta.get('album', ''))
        
        # Update Cover
        cover_path = meta.get('cover_path')
        if cover_path and os.path.exists(cover_path):
            try:
                img = Image.open(cover_path)
                img.thumbnail((200, 200)) # Resize
                photo = ImageTk.PhotoImage(img)
                self.cover_label.config(image=photo)
                self.cover_label.image = photo # Keep reference
            except Exception as e:
                print(f"Error loading cover image: {e}")
                self.cover_label.config(image=self.default_cover)
        else:
            self.cover_label.config(image=self.default_cover)

        # Update Lyrics
        self.lyrics_text.config(state=tk.NORMAL)
        self.lyrics_text.delete(1.0, tk.END)
        self.active_lyric_index = -1  # Reset index to force re-highlighting on new lyrics
        lyrics = meta.get('lyrics')
        
        self.parsed_lyrics = []
        if lyrics:
            # Check if it's lrc format (contains timestamps)
            if re.search(r'\[\d{2}:\d{2}', lyrics):
                self._parse_and_display_lrc(lyrics)
            else:
                self.lyrics_text.insert(tk.END, lyrics)
        else:
            self.lyrics_text.insert(tk.END, "未找到歌词。")
            
        self.lyrics_text.config(state=tk.DISABLED)

    def _parse_and_display_lrc(self, lyrics_text):
        lines = lyrics_text.splitlines()
        regex = re.compile(r'\[(\d{2}):(\d{2}(?:\.\d+)?)\](.*)')
        
        parsed = []
        for line in lines:
            match = regex.match(line)
            if match:
                minutes = int(match.group(1))
                seconds = float(match.group(2))
                timestamp = minutes * 60 + seconds
                content = match.group(3).strip()
                if content: # Skip empty lines
                    parsed.append((timestamp, content))
        
        # Sort by timestamp
        parsed.sort(key=lambda x: x[0])
        self.parsed_lyrics = parsed
        
        # Insert into text widget
        for _, content in self.parsed_lyrics:
            self.lyrics_text.insert(tk.END, content + "\n", "center")

    def toggle_play(self):
        if self.current_index == -1:
            if self.playlist:
                self.play_index(0)
            return

        if self.player.is_playing() or self.player.paused:
            if self.player.paused:
                self.player.play()
                self.play_btn.config(text="⏸ 暂停")
                self.status_var.set(f"正在播放")
            else:
                self.player.pause()
                self.play_btn.config(text="▶ 播放")
                self.status_var.set("已暂停")
        else:
            self.play_index(self.current_index)

    def stop_song(self):
        self.player.stop()
        self.play_btn.config(text="▶ 播放")
        self.status_var.set("已停止")
        self.time_var.set("00:00 / 00:00")
        self.progress_var.set(0)
        self.is_seeking = False

    def on_seek_press(self, event):
        self.is_seeking = True

    def on_seek_drag(self, value):
        # Optional: Update time label while dragging
        if self.current_duration > 0:
             current_seconds = (float(value) / 100.0) * self.current_duration
             self.time_var.set(f"{self.format_time(current_seconds)} / {self.format_time(self.current_duration)}")

    def on_seek_release(self, event):
        if self.current_duration > 0:
            seek_pos = self.progress_scale.get()
            seek_seconds = (seek_pos / 100.0) * self.current_duration
            self.player.seek(seek_seconds)
            
            # If was paused, play button needs to update to Pause
            if not self.player.paused:
                self.play_btn.config(text="⏸ Pause")
        
        # Small delay to prevent update loop from snapping back immediately
        self.root.after(500, lambda: setattr(self, 'is_seeking', False))

    def next_song(self):
        if self.playlist:
            next_idx = (self.current_index + 1) % len(self.playlist)
            self.play_index(next_idx)

    def prev_song(self):
        if self.playlist:
            prev_idx = (self.current_index - 1) % len(self.playlist)
            self.play_index(prev_idx)

    def set_volume(self, val):
        volume = float(val) / 100
        self.player.set_volume(volume)

    def format_time(self, seconds):
        minutes = int(seconds // 60)
        seconds = int(seconds % 60)
        return f"{minutes:02d}:{seconds:02d}"

    def update_status(self):
        if self.current_index != -1 and (self.player.is_playing() or self.player.paused):
            current_time = self.player.get_position()
            total_time = self.current_duration
            self.time_var.set(f"{self.format_time(current_time)} / {self.format_time(total_time)}")
            
            # Update progress bar if not seeking
            if not self.is_seeking and total_time > 0:
                progress = (current_time / total_time) * 100
                self.progress_var.set(progress)
            
            # Sync lyrics
            if self.parsed_lyrics:
                # Find current lyric index
                # We want the last lyric that has timestamp <= current_time
                new_index = -1
                for i, (ts, _) in enumerate(self.parsed_lyrics):
                    if ts <= current_time:
                        new_index = i
                    else:
                        break
                
                if new_index != -1 and new_index != self.active_lyric_index:
                    self.active_lyric_index = new_index
                    
                    # Line numbers in Text widget start at 1
                    line_num = new_index + 1
                    
                    # Update highlighting
                    self.lyrics_text.tag_remove("current_line", "1.0", tk.END)
                    self.lyrics_text.tag_add("current_line", f"{line_num}.0", f"{line_num}.end")
                    
                    # Scroll to ensure line is visible and near top
                    # see() ensures visibility, but not necessarily at top
                    # yview_moveto or yview(index) puts line at top
                    self.lyrics_text.see(f"{line_num}.0")
                    self.lyrics_text.yview(f"{line_num}.0")
        
        # Check for auto next
        if self.current_index != -1 and not self.player.is_playing() and not self.player.paused:
             if not self.player.paused:
                 if self.playlist and len(self.playlist) > 0:
                     self.next_song()

        # Schedule next update
        self.root.after(200, self.update_status) # Update faster for smoother lyrics
    
    def show_id3_window(self):
        if self.current_index == -1 or not self.playlist:
            messagebox.showinfo("提示", "请先选择歌曲。")
            return
        file_path = self.playlist[self.current_index]
        try:
            audio = File(file_path)
        except Exception as e:
            messagebox.showerror("错误", f"无法读取标签:\n{e}")
            return
        if not audio or not getattr(audio, "tags", None):
            messagebox.showinfo("提示", "未找到标签信息。")
            return
        win = tk.Toplevel(self.root)
        win.title("ID3 标签")
        win.geometry("600x500")
        header = ttk.Label(win, text=os.path.basename(file_path), font=('Arial', 12, 'bold'))
        header.pack(pady=8)
        frame = ttk.Frame(win)
        frame.pack(fill=tk.BOTH, expand=True)
        text = tk.Text(frame, wrap=tk.NONE, font=('Segoe UI', 10))
        xscroll = ttk.Scrollbar(frame, orient=tk.HORIZONTAL, command=text.xview)
        yscroll = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=text.yview)
        text.config(xscrollcommand=xscroll.set, yscrollcommand=yscroll.set)
        text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        yscroll.pack(side=tk.RIGHT, fill=tk.Y)
        xscroll.pack(side=tk.BOTTOM, fill=tk.X)
        try:
            tags = audio.tags
            lines = []
            for k in tags.keys():
                v = tags.get(k)
                val = ""
                try:
                    if hasattr(v, "text"):
                        val = " | ".join(map(str, getattr(v, "text")))
                    elif hasattr(v, "data") and isinstance(getattr(v, "data"), (bytes, bytearray)):
                        val = f"<{len(getattr(v, 'data'))} bytes>"
                    elif isinstance(v, (list, tuple)):
                        val = " | ".join([self._to_str(x) for x in v])
                    else:
                        val = self._to_str(v)
                except Exception:
                    val = str(v)
                lines.append(f"{k}: {val}")
            for line in lines:
                text.insert(tk.END, line + "\n")
            text.config(state=tk.DISABLED)
        except Exception as e:
            messagebox.showerror("错误", f"解析标签失败:\n{e}")
            win.destroy()
            return
    
    def _to_str(self, v):
        try:
            return str(v)
        except Exception:
            return repr(v)

if __name__ == "__main__":
    root = tk.Tk()
    app = MusicPlayerGUI(root)
    root.mainloop()

import pygame
import os
import shutil
import subprocess
from mutagen import File
import imageio_ffmpeg
import platform

class MusicPlayer:
    def __init__(self):
        pygame.mixer.init()
        self.current_file = None
        self.current_file_obj = None  # Handle for open file object
        self.temp_file = None
        self.paused = False
        self.start_time = 0.0  # Track start position for seeking
        self.volume = 0.5
        pygame.mixer.music.set_volume(self.volume)
        
        # Create temp dir
        self.temp_dir = os.path.join(os.getcwd(), "temp_audio")
        if not os.path.exists(self.temp_dir):
            os.makedirs(self.temp_dir)

    def __del__(self):
        self.cleanup_temp()

    def cleanup_temp(self):
        # Stop playback before deleting files
        try:
            pygame.mixer.music.unload()
        except:
            pass
            
        if self.current_file_obj:
            try:
                self.current_file_obj.close()
            except:
                pass
            self.current_file_obj = None

        if self.temp_dir and os.path.exists(self.temp_dir):
            try:
                shutil.rmtree(self.temp_dir)
            except:
                pass

    def load_file(self, file_path):
        if not os.path.exists(file_path):
            raise FileNotFoundError("File not found")

        # Cleanup previous file object if any
        if self.current_file_obj:
            try:
                self.current_file_obj.close()
            except:
                pass
            self.current_file_obj = None

        self.current_file = file_path
        self.start_time = 0.0
        
        # On macOS, force FFmpeg conversion for AAC/M4A/MP4 to avoid SDL_mixer issues
        ext = os.path.splitext(file_path)[1].lower()
        if platform.system() == 'Darwin' and ext in ('.m4a', '.mp4', '.aac'):
            return self._load_via_conversion(file_path)

        # Optimistic loading: Try to load directly with pygame first.
        # Use file object to handle unicode paths better on some systems
        try:
            self.current_file_obj = open(file_path, 'rb')
            pygame.mixer.music.load(self.current_file_obj)
            return self._get_duration(file_path)
        except (pygame.error, OSError) as e:
            # If direct load fails, close the file object
            if self.current_file_obj:
                try:
                    self.current_file_obj.close()
                except:
                    pass
                self.current_file_obj = None

            # Fallback to conversion if pygame fails (e.g. AAC masquerading as MP3, DSF, etc.)
            # "ModPlug_Load failed" is a common error when SDL_mixer tries its last-resort loader on unsupported formats
            error_msg = str(e)
            if "ModPlug" in error_msg:
                print(f"Format mismatch detected (likely AAC/M4A in MP3 container). Switching to FFmpeg conversion for: {os.path.basename(file_path)}")
            else:
                print(f"Direct load failed (Error: {e}). Switching to FFmpeg conversion for: {os.path.basename(file_path)}")
            pass
        
        # Convert to ogg using ffmpeg directly (for reliable seeking on unsupported formats)
        return self._load_via_conversion(file_path)

    def _load_via_conversion(self, file_path):
        try:
            # Unload previous file to release lock
            try:
                pygame.mixer.music.unload()
            except Exception:
                pass

            # Generate temp file path with unique name
            import uuid
            # Use .ogg for better seeking support in pygame
            temp_file = os.path.join(self.temp_dir, f"playback_{uuid.uuid4().hex}.ogg")
            ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
            
            # Convert directly using ffmpeg
            # -vn: disable video
            # -ar 44100: resample to 44.1kHz
            # -acodec libvorbis: use Vorbis codec for OGG
            process = subprocess.run([
                ffmpeg_exe, 
                '-y', 
                '-i', file_path, 
                '-vn',
                '-ar', '44100',
                '-acodec', 'libvorbis',
                temp_file
            ], capture_output=True, check=True)
            
            # Load into pygame
            pygame.mixer.music.load(temp_file)
            
            # Clean up previous temp file
            if self.temp_file and os.path.exists(self.temp_file) and self.temp_file != temp_file:
                try:
                    os.remove(self.temp_file)
                except:
                    pass
                    
            self.temp_file = temp_file
            
            # Get duration
            return self._get_duration(temp_file)
        except subprocess.CalledProcessError as e:
            print(f"FFmpeg Error: {e.stderr.decode('utf-8', errors='ignore')}")
            raise e
        except Exception as e:
            print(f"Error converting/loading file: {e}")
            raise e

    def _get_duration(self, file_path):
        try:
            audio = File(file_path)
            if audio is not None and audio.info is not None:
                return audio.info.length
        except:
            pass
        return 0

    def play(self):
        if self.current_file:
            if self.paused:
                pygame.mixer.music.unpause()
                self.paused = False
            else:
                self.start_time = 0.0
                pygame.mixer.music.play()

    def pause(self):
        if self.current_file and not self.paused:
            pygame.mixer.music.pause()
            self.paused = True

    def stop(self):
        pygame.mixer.music.stop()
        self.paused = False
        self.start_time = 0.0

    def set_volume(self, volume):
        # volume: 0.0 to 1.0
        self.volume = max(0.0, min(1.0, volume))
        pygame.mixer.music.set_volume(self.volume)
        
    def seek(self, position):
        if self.current_file:
            try:
                # Play from new position
                # Note: 'start' argument works for MP3 and OGG (absolute time)
                pygame.mixer.music.play(start=position)
                self.start_time = position
                # If was paused, this will resume it, so update state
                self.paused = False
            except pygame.error as e:
                print(f"Seek error: {e}")

    def is_playing(self):
        return pygame.mixer.music.get_busy()

    def get_position(self):
        # Returns current position in seconds
        if self.current_file:
            pos = pygame.mixer.music.get_pos()
            if pos == -1:
                return 0.0
            return self.start_time + (pos / 1000.0)
        return 0.0

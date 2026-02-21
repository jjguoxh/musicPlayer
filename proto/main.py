from gui import MusicPlayerGUI
import tkinter as tk
import pygame

if __name__ == "__main__":
    # Initialize pygame mixer early to ensure it's ready
    pygame.mixer.init()
    
    root = tk.Tk()
    # Set icon if available (skip for now)
    
    app = MusicPlayerGUI(root)
    
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass
    finally:
        pygame.mixer.quit()

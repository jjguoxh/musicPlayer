import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var vm: PlayerViewModel
    @Binding var isSidebarVisible: Bool
    @Binding var showImporter: Bool
    @State private var expandedPlaylists: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Music Player")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedFileTypes = ["mp3","m4a","wav","aac","flac","aiff"]
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK {
                        vm.addLocalFiles(urls: panel.urls)
                    }
                } label: {
                    Label("导入音乐", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    vm.clearLibrary()
                } label: {
                    Label("清空列表", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .padding(.top, 20)
            
            List {
                Section("播放列表") {
                    ForEach(vm.playlists) { playlist in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedPlaylists.contains(playlist.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedPlaylists.insert(playlist.id)
                                    } else {
                                        expandedPlaylists.remove(playlist.id)
                                    }
                                }
                            )
                        ) {
                            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    vm.play(playlistId: playlist.id, index: index)
                                    withAnimation { isSidebarVisible = false }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(track.title)
                                                .font(.body)
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if vm.currentPlaylistId == playlist.id && vm.currentIndex == index {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                vm.delete(atOffsets: offsets, fromPlaylistId: playlist.id)
                            }
                        } label: {
                            Text(playlist.name).font(.headline)
                        }
                    }
                }
            }
        }
    }
}

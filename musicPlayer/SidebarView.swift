
import SwiftUI

struct SidebarView: View {
    @ObservedObject var vm: PlayerViewModel
    @Binding var isSidebarVisible: Bool
    @Binding var showImporter: Bool
    @State private var expandedPlaylists: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Music Player")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            .padding(.top, 40)
            
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
                                    withAnimation {
                                        isSidebarVisible = false
                                    }
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
                            Text(playlist.name)
                                .font(.headline)
                        }
                    }
                }
                
                Section("功能") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入音乐", systemImage: "square.and.arrow.down")
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        Label("关于", systemImage: "info.circle")
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.blue)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(20)
            
            Text("Music Player")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Designed by JJGuoxh")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("关于")
    }
}

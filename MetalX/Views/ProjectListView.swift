import SwiftUI

public struct ProjectListView: View {
    @StateObject private var projectList = ProjectListModel()
    @State private var showingNewProjectSheet = false
    @State private var selectedProject: MetalXProject?
    @State private var showingDeleteConfirmation = false
    @State private var projectToDelete: MetalXProject?
    
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                if projectList.projects.isEmpty {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 500)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 300), spacing: 20)
                    ], spacing: 20) {
                        ForEach(projectList.projects, id: \.id) { project in
                            NavigationLink(value: project) {
                                ProjectCard(
                                    project: project,
                                    onDelete: {
                                        projectToDelete = project
                                        showingDeleteConfirmation = true
                                    }
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Projects")
            // Value-based navigation destination for projects
            .navigationDestination(for: MetalXProject.self) { project in
                CanvasEditorView(project: project, projectList: projectList)
            }
//            .toolbar {
//                ToolbarItem(placement: .primaryAction) {
//                    Button(action: {
//                        showingNewProjectSheet = true
//                    }) {
//                        Label("New Project", systemImage: "plus")
//                    }
//                }
//            }
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectView(isPresented: $showingNewProjectSheet) { name, preset in
                    let project = projectList.createNewProject(name: name, preset: preset)
                    selectedProject = project
                }
            }
            .confirmationDialog(
                "Delete Project",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let project = projectToDelete {
                        projectList.deleteProject(project)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if let project = projectToDelete {
                    Text("Are you sure you want to delete \"\(project.name)\"? This cannot be undone.")
                }
            }
            
//            .navigationDestination(for: $selectedProject) { project in
//                CanvasEditorView(project: project, projectList: projectList)
//            }
            .onAppear {
                projectList.loadProjects()
            }
        }
    }
}

struct ProjectCard: View {
    let project: MetalXProject
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var showingOptions = false
    @State private var thumbnail: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail area
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
                .overlay(alignment: .topTrailing) {
                    // Show menu button on iOS, delete on hover for macOS
                    #if os(iOS)
                    Menu {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(8)
                    #else
                    if isHovering {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        .padding(8)
                    }
                    #endif
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(project.modifiedDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(project.layers.count) layers • \(Int(project.canvasSize.width))×\(Int(project.canvasSize.height))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onAppear(perform: loadThumbnail)
    }

    private func loadThumbnail() {
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent("MetalXProjects").appendingPathComponent("\(project.id.uuidString).png")
            if fm.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                thumbnail = img
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No Projects Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create your first project to get started")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ProjectListView()
}

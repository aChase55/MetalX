# Undo/Redo System Specification

## Overview
A sophisticated non-linear undo/redo system with memory efficiency, branching history, selective undo, and collaborative undo support.

## Core Architecture

### 1. Command Pattern Implementation

```swift
// Base command protocol
protocol UndoableCommand {
    var id: UUID { get }
    var timestamp: Date { get }
    var description: String { get }
    var memoryFootprint: Int { get }
    var canCoalesce: Bool { get }
    
    func execute() throws
    func undo() throws
    func redo() throws
    func validate() -> Bool
}

// Command with state capture
protocol StatefulCommand: UndoableCommand {
    associatedtype State
    var previousState: State { get set }
    var newState: State { get set }
}

// Lightweight command using references
protocol LightweightCommand: UndoableCommand {
    var targetID: UUID { get }
    var operation: Operation { get }
    var parameters: [String: Any] { get }
}
```

### 2. History Management

```swift
class HistoryManager {
    // History structure
    private var mainBranch: HistoryBranch
    private var branches: [UUID: HistoryBranch] = [:]
    private var currentBranch: UUID
    private var currentIndex: Int
    
    // Memory management
    private let memoryBudget: Int
    private var currentMemoryUsage: Int = 0
    private let compressionQueue = DispatchQueue(label: "history.compression")
    
    // History node
    class HistoryNode {
        let command: UndoableCommand
        var children: [HistoryNode] = []
        weak var parent: HistoryNode?
        let branchPoint: Bool
        var compressed: Bool = false
        var compressionData: Data?
        
        // Lazy loading
        func decompress() throws -> UndoableCommand {
            if compressed, let data = compressionData {
                return try CommandSerializer.deserialize(data)
            }
            return command
        }
    }
    
    // Branch management
    struct HistoryBranch {
        var id: UUID
        var name: String
        var root: HistoryNode
        var current: HistoryNode
        var metadata: BranchMetadata
    }
}
```

### 3. Memory-Efficient Command Storage

```swift
class CommandStorage {
    // Command compression
    enum CompressionStrategy {
        case none
        case snapshot(interval: Int)
        case delta
        case hybrid
    }
    
    // Differential storage
    class DeltaCommand: UndoableCommand {
        private let delta: Data
        private let baseSnapshotID: UUID
        
        func execute() throws {
            let baseSnapshot = try loadSnapshot(baseSnapshotID)
            let newState = try applyDelta(delta, to: baseSnapshot)
            try applyState(newState)
        }
        
        func undo() throws {
            let baseSnapshot = try loadSnapshot(baseSnapshotID)
            try applyState(baseSnapshot)
        }
    }
    
    // Snapshot management
    class SnapshotManager {
        private var snapshots: [UUID: Snapshot] = [:]
        private let snapshotInterval = 10 // Commands between snapshots
        
        struct Snapshot {
            let id: UUID
            let timestamp: Date
            let state: Data
            let compressed: Bool
            let dependencies: Set<UUID>
        }
        
        func shouldCreateSnapshot(commandCount: Int) -> Bool {
            return commandCount % snapshotInterval == 0
        }
        
        func createSnapshot(state: State) -> Snapshot {
            let compressed = CompressedState(state)
            return Snapshot(
                id: UUID(),
                timestamp: Date(),
                state: compressed.data,
                compressed: true,
                dependencies: state.dependencies
            )
        }
    }
}
```

### 4. Non-Linear History

```swift
extension HistoryManager {
    // Branching operations
    func createBranch(name: String, from node: HistoryNode) -> HistoryBranch {
        let branch = HistoryBranch(
            id: UUID(),
            name: name,
            root: node,
            current: node,
            metadata: BranchMetadata(
                createdAt: Date(),
                author: currentUser,
                description: "Branch from \(node.command.description)"
            )
        )
        
        branches[branch.id] = branch
        node.branchPoint = true
        
        return branch
    }
    
    // Merge branches
    func mergeBranch(_ source: HistoryBranch, 
                    into target: HistoryBranch) throws -> MergeResult {
        // Find common ancestor
        let ancestor = findCommonAncestor(source, target)
        
        // Collect commands from both branches
        let sourceCommands = collectCommands(from: ancestor, to: source.current)
        let targetCommands = collectCommands(from: ancestor, to: target.current)
        
        // Detect conflicts
        let conflicts = detectConflicts(sourceCommands, targetCommands)
        
        if conflicts.isEmpty {
            // Auto-merge
            return try autoMerge(sourceCommands, into: target)
        } else {
            // Interactive conflict resolution
            return .needsResolution(conflicts)
        }
    }
    
    // Time-based navigation
    func goToTime(_ timestamp: Date) {
        let targetNode = findNodeNearestTo(timestamp)
        navigateToNode(targetNode)
    }
}
```

### 5. Selective Undo

```swift
class SelectiveUndoManager {
    // Undo specific commands
    func undoCommands(_ commandIDs: Set<UUID>) throws {
        // Build dependency graph
        let graph = buildDependencyGraph()
        
        // Find affected commands
        let affected = findAffectedCommands(commandIDs, in: graph)
        
        // Check if selective undo is safe
        if let conflicts = findConflicts(affected, currentState) {
            throw UndoError.conflictingState(conflicts)
        }
        
        // Create compensating commands
        let compensatingCommands = try createCompensatingCommands(for: commandIDs)
        
        // Execute compensations
        for command in compensatingCommands {
            try command.execute()
            addToHistory(command)
        }
    }
    
    // Layer-specific undo
    func undoLayer(_ layerID: UUID, steps: Int = 1) throws {
        let layerCommands = history.filter { command in
            command.affectsLayer(layerID)
        }
        
        let toUndo = Array(layerCommands.suffix(steps))
        try undoCommands(Set(toUndo.map { $0.id }))
    }
    
    // Effect-specific undo
    func undoEffect(_ effectID: UUID) throws {
        let effectCommands = history.filter { command in
            command.affectsEffect(effectID)
        }
        
        try undoCommands(Set(effectCommands.map { $0.id }))
    }
}
```

### 6. Command Coalescing

```swift
class CommandCoalescer {
    private var pendingCommands: [UndoableCommand] = []
    private var coalescingTimer: Timer?
    private let coalescingDelay: TimeInterval = 0.5
    
    // Coalescing rules
    struct CoalescingRule {
        let canCoalesce: (UndoableCommand, UndoableCommand) -> Bool
        let coalesce: (UndoableCommand, UndoableCommand) -> UndoableCommand
    }
    
    private let rules: [CoalescingRule] = [
        // Text input coalescing
        CoalescingRule(
            canCoalesce: { cmd1, cmd2 in
                cmd1 is TextInputCommand && cmd2 is TextInputCommand &&
                cmd1.timestamp.distance(to: cmd2.timestamp) < 0.5
            },
            coalesce: { cmd1, cmd2 in
                let text1 = cmd1 as! TextInputCommand
                let text2 = cmd2 as! TextInputCommand
                return TextInputCommand(
                    text: text1.text + text2.text,
                    range: text1.range.union(text2.range)
                )
            }
        ),
        
        // Transform coalescing
        CoalescingRule(
            canCoalesce: { cmd1, cmd2 in
                cmd1 is TransformCommand && cmd2 is TransformCommand &&
                (cmd1 as! TransformCommand).targetID == (cmd2 as! TransformCommand).targetID
            },
            coalesce: { cmd1, cmd2 in
                let t1 = cmd1 as! TransformCommand
                let t2 = cmd2 as! TransformCommand
                return TransformCommand(
                    targetID: t1.targetID,
                    transform: t1.transform.concatenating(t2.transform)
                )
            }
        )
    ]
    
    func addCommand(_ command: UndoableCommand) {
        coalescingTimer?.invalidate()
        
        if let lastCommand = pendingCommands.last,
           let rule = findMatchingRule(lastCommand, command),
           rule.canCoalesce(lastCommand, command) {
            // Replace with coalesced command
            pendingCommands[pendingCommands.count - 1] = rule.coalesce(lastCommand, command)
        } else {
            pendingCommands.append(command)
        }
        
        // Reset timer
        coalescingTimer = Timer.scheduledTimer(withTimeInterval: coalescingDelay, repeats: false) { _ in
            self.flushPendingCommands()
        }
    }
}
```

### 7. Collaborative Undo

```swift
class CollaborativeUndoManager {
    // Operation transformation for undo
    func transformUndoForCollaboration(_ undo: UndoableCommand,
                                      against concurrentOps: [Operation]) -> UndoableCommand {
        var transformedUndo = undo
        
        for op in concurrentOps {
            transformedUndo = transform(transformedUndo, against: op)
        }
        
        return transformedUndo
    }
    
    // Collaborative undo modes
    enum UndoScope {
        case local      // Only undo my changes
        case shared     // Undo visible to all
        case selective  // Choose which users see the undo
    }
    
    func collaborativeUndo(scope: UndoScope) throws {
        let command = currentBranch.current
        
        switch scope {
        case .local:
            // Create local compensation
            let compensation = createLocalCompensation(for: command)
            try compensation.execute()
            
        case .shared:
            // Broadcast undo operation
            let undoOp = UndoOperation(
                commandID: command.id,
                userId: currentUser.id,
                timestamp: Date()
            )
            broadcastOperation(undoOp)
            
        case .selective(let users):
            // Selective visibility
            let selectiveUndo = SelectiveUndoOperation(
                commandID: command.id,
                visibleTo: users
            )
            broadcastSelectiveOperation(selectiveUndo)
        }
    }
}
```

### 8. Undo Visualization

```swift
class UndoHistoryVisualizer {
    // Visual history tree
    func generateHistoryTree() -> HistoryTreeView {
        let tree = HistoryTreeView()
        
        // Build tree structure
        for branch in branches {
            let branchView = createBranchView(branch)
            tree.addBranch(branchView)
        }
        
        // Add timeline
        tree.timeline = createTimeline(from: allNodes)
        
        // Add metadata overlays
        tree.addOverlay(.memoryUsage(calculateMemoryMap()))
        tree.addOverlay(.userActivity(getUserActivityMap()))
        
        return tree
    }
    
    // Interactive history scrubbing
    class HistoryScrubber: UIView {
        var onScrub: ((HistoryNode) -> Void)?
        
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            
            let location = touch.location(in: self)
            let progress = location.x / bounds.width
            
            // Find node at progress
            let node = nodeAtProgress(progress)
            
            // Show preview
            showPreview(of: node)
            
            // Haptic feedback at nodes
            if nodeChanged(from: previousNode, to: node) {
                generateHapticFeedback()
            }
        }
    }
}
```

### 9. Performance Optimizations

```swift
extension HistoryManager {
    // Async history operations
    func addCommandAsync(_ command: UndoableCommand) async {
        // Add immediately for responsiveness
        await MainActor.run {
            temporaryAdd(command)
        }
        
        // Process in background
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.compressOldCommands()
            }
            
            group.addTask {
                await self.updateSnapshots()
            }
            
            group.addTask {
                await self.pruneHistory()
            }
        }
    }
    
    // Memory pressure handling
    func handleMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .normal:
            break
            
        case .warning:
            // Compress recent commands
            compressCommands(olderThan: .minutes(5))
            
        case .critical:
            // Aggressive pruning
            keepOnlyEssentialHistory()
            swapToDisk(branches: inactiveBranches)
        }
    }
    
    // Intelligent pruning
    func pruneHistory() {
        // Keep all commands from last hour
        let recentCutoff = Date().addingTimeInterval(-3600)
        
        // Keep every Nth command from last day
        let dayCutoff = Date().addingTimeInterval(-86400)
        
        // Keep only major commands older than a day
        let majorCommands = commands.filter { command in
            command.timestamp < dayCutoff && command.isMajor
        }
        
        // Rebuild history with pruned commands
        rebuildHistory(keeping: recentCommands + sampledCommands + majorCommands)
    }
}
```

### 10. Persistence and Recovery

```swift
class UndoHistoryPersistence {
    // Save history to disk
    func saveHistory(_ history: HistoryManager) async throws {
        let encoder = HistoryEncoder()
        
        // Encode metadata
        let metadata = HistoryMetadata(
            version: 1,
            branches: history.branches.count,
            totalCommands: history.totalCommands,
            memoryUsage: history.memoryUsage
        )
        
        // Encode branches
        for branch in history.branches {
            let encoded = try encoder.encodeBranch(branch)
            try await saveBranch(encoded, id: branch.id)
        }
        
        // Save metadata
        try await saveMetadata(metadata)
    }
    
    // Crash recovery
    func recoverFromCrash() async throws -> HistoryManager? {
        // Find incomplete operations
        let incompleteOps = try await findIncompleteOperations()
        
        // Validate history integrity
        let validHistory = try await validateAndRepairHistory()
        
        // Restore to last known good state
        let recovered = HistoryManager()
        recovered.restore(from: validHistory)
        
        // Offer to replay incomplete operations
        if !incompleteOps.isEmpty {
            recovered.incompleteOperations = incompleteOps
        }
        
        return recovered
    }
}
```

## Best Practices

1. **Command Granularity**: Keep commands atomic and focused
2. **Memory Efficiency**: Use delta compression for large state changes
3. **Coalescing**: Implement intelligent coalescing for smooth UX
4. **Validation**: Always validate commands before execution
5. **Branching**: Use branches for experimental edits
6. **Persistence**: Regularly checkpoint history to disk
7. **Performance**: Use async operations for heavy processing
8. **Collaboration**: Transform operations for conflict-free undo
9. **Visualization**: Provide clear history visualization
10. **Recovery**: Implement robust crash recovery
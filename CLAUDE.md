# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ContainEye is a comprehensive server monitoring solution consisting of:

1. **iOS/macOS App**: SwiftUI-based client application for remote server monitoring
2. **Backend API**: Vapor-based server for push notifications and centralized services

### Main Features
- **Server Monitoring**: Real-time CPU, memory, disk, and network metrics via SSH
- **Container Management**: Docker container oversight and control
- **SFTP File Transfer**: Remote file system browsing, management, and file upload capabilities
- **SSH Terminal Access**: xterm.js-based terminal emulation via WKWebView
- **Automated Testing**: Configurable server health checks with background execution
- **Widget Support**: iOS widgets for quick server status overview
- **Push Notifications**: Backend-powered alerts for critical server events

## Architecture

### Core Technologies
**iOS/macOS App:**
- **SwiftUI** with Swift 6.0 and strict concurrency
- **Blackbird SQLite** for local data persistence with reactive UI updates
- **Citadel/CSSH** for SSH and SFTP operations
- **KeychainAccess** for secure credential storage with iCloud sync
- **xterm.js + WKWebView** for terminal emulation with OSC shell integration
- **TelemetryDeck** for analytics

**Backend API:**
- **Vapor 4** web framework with Swift 6.0
- **PostgreSQL** with Fluent ORM
- **Apple Push Notification Service (APNS)** integration
- **Docker** containerization with multi-stage builds

### Data Architecture
**Core Data Models (Blackbird):**
- `Server`: Core server entity with metrics, connection state, and hardware info
- `Container`: Docker container representation with real-time usage stats
- `Process`: System process information with CPU/memory tracking
- `ServerTest`: Automated test definitions with regex pattern matching and status tracking
- `Credential`: SSH credentials securely stored in Keychain (not database)

**Key Relationships:**
- Server (1:N) Containers, Processes, ServerTests
- Credentials referenced by key, stored separately in Keychain
- App Group database sharing for widget extensions

### Architectural Patterns
- **Actor-based Concurrency**: `SSHClientActor` singleton for thread-safe SSH connection management
- **Reactive Database**: `@BlackbirdLiveModels` for automatic SwiftUI updates
- **Background Processing**: `BGTaskScheduler` for automated server testing
- **Environment-based DI**: Database and namespace injection through SwiftUI environment
- **App Intents Integration**: Siri shortcuts and system integration for ServerTests

## Development Commands

### iOS/macOS App
```bash
# Build for iOS Simulator (now supported!)
xcodebuild -scheme ContainEye -destination 'platform=iOS Simulator,arch=arm64,id=SIMULATOR_ID' build

# Build for macOS
xcodebuild -scheme ContainEye -destination 'platform=macOS' build

# Run tests
xcodebuild -scheme ContainEye -destination 'platform=iOS Simulator,arch=arm64,id=SIMULATOR_ID' test

# Build widget extension
xcodebuild -scheme TestsWidgetExtension -destination 'platform=iOS Simulator,arch=arm64,id=SIMULATOR_ID' build

# Find available simulators
xcrun simctl list devices available
```

### Backend API
```bash
# Development (from containeye-backend directory)
swift run App serve --hostname 0.0.0.0 --port 8080

# Run tests
swift test

# Docker development
docker compose up app

# Production build
docker compose build
docker compose up -d
```

## Project Structure

### iOS/macOS App (`ContainEye/`)
- `App/`: App lifecycle, delegate, and main app entry point
- `Data/`: Core data models, database management, SSH client actor
- `Shared/`: Reusable UI components, utilities, and setup flows
- `Server/`: Server monitoring views and detail screens
- `Tests/`: Server testing interface and configuration
- `SFTP/`: File management and transfer views
- `TerminalTab/`: xterm-based SSH terminal workspace (multi-tab/pane) with snippet management
- `AppIntents/`: Siri shortcuts and app intents implementation
- `Assets.xcassets/`: App icons and image assets

### Backend API (`containeye-backend/`)
- `Sources/App/`: Vapor application source code
  - `Controllers/`: API route handlers
  - `Models/`: Database models (Fluent)
  - `Migrations/`: Database schema migrations
- `Tests/AppTests/`: Backend unit tests
- `Public/`: Static assets served by Vapor
- `Dockerfile`: Multi-stage production container build
- `docker-compose.yml`: Development environment setup

### Widget Extension (`TestsWidget/`)
- iOS widget implementation for server test status overview

## Key Implementation Details

### SSH Connection Management
- `SSHClientActor`: Singleton actor managing SSH connection pools
- Automatic connection lifecycle management with proper cleanup
- Citadel for command/SFTP operations, SwiftSH for interactive shell streaming
- **SwiftSH**: Built from source for full simulator support (replaced binary framework)
- Comprehensive error handling for network and authentication failures

### Server Metrics Collection
- System commands executed via SSH: `sar`, `free`, `df`, `ps`, `docker stats`
- Real-time parsing of Linux command output
- Automatic hardware detection (CPU cores, total memory/disk)
- Connection state tracking with automatic reconnection

### Testing System Architecture
- Tests defined with shell commands and regex expected output patterns
- Background execution via `BGTaskScheduler` for iOS background processing
- Default test templates loaded from embedded `DefaultTests.json`
- Supports both server-specific tests and HTTP endpoint monitoring
- App Intents integration for Siri/Shortcuts automation
- Retry logic with exponential backoff for failed tests

### Database Integration
- **Blackbird SQLite**: Reactive ORM with automatic UI updates
- **App Group Database**: Shared database in `group.com.nagel.ContainEye` for widget access
- **Transaction-based Updates**: Bulk operations for process/container data
- **Custom Enum Support**: `BlackbirdStringEnum` for typed database fields

### Security Implementation
- **Keychain Storage**: All SSH credentials stored with iCloud sync capability
- **App Group Keychain**: Shared keychain access for extensions
- **No Credential Persistence**: Credentials never stored in SQLite database
- **Secure Command Execution**: All remote commands executed through established SSH channels

### Push Notification Backend
- **Vapor + APNS**: Centralized notification service
- **PostgreSQL Database**: Device registration and notification tracking
- **Docker Deployment**: Production-ready containerization

## Development Notes

### iOS/macOS App
- **Swift 6.0** with strict concurrency checking enabled
- **Deployment Targets**: iOS 18.0+ and macOS 15.0+
- **Modern SwiftUI**: Uses `@Observable` macro and latest SwiftUI patterns
- **Comprehensive Error Handling**: Custom `ServerError` and `DataStreamerError` types
- **Telemetry Integration**: User opt-in analytics with TelemetryDeck

### Backend API
- **Swift 6.0** server-side development
- **PostgreSQL** production database with Fluent ORM
- **Multi-stage Docker**: Optimized production builds with static linking
- **APNS Integration**: Production push notification support

### Default Test Configuration
The app includes predefined health checks in `DefaultTests.json`:
- HTTP endpoint availability (curl-based)
- Disk space monitoring (df command)
- Memory usage validation (free command)
- Service status verification (systemctl)
- Docker container health checks
- Security monitoring (failed login attempts)

All tests support regex pattern matching for flexible output validation and custom success criteria.

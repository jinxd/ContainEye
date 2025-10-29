//
//  Server.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import Foundation
import NIO
@preconcurrency import Citadel
import KeychainAccess
import Foundation
import Blackbird

struct Server: BlackbirdModel {
    
    static let primaryKey: [BlackbirdColumnKeyPath] = [\.$id]

    @BlackbirdColumn var id: String
    @BlackbirdColumn var credentialKey: String
    @BlackbirdColumn var cpuUsage: Double?
    @BlackbirdColumn var memoryUsage: Double?
    @BlackbirdColumn var diskUsage: Double?
    @BlackbirdColumn var networkUpstream: Double?
    @BlackbirdColumn var networkDownstream: Double?
    @BlackbirdColumn var swapUsage: Double?
    @BlackbirdColumn var systemLoad: Double?
    @BlackbirdColumn var ioWait: Double?
    @BlackbirdColumn var stealTime: Double?
    @BlackbirdColumn var uptime: Date?
    @BlackbirdColumn var lastUpdate: Date?
    @BlackbirdColumn var isConnected: Bool
    @BlackbirdColumn var totalDiskSpace: Double?
    @BlackbirdColumn var totalMemory: Double?
    @BlackbirdColumn var cpuCores: Int?
    @BlackbirdColumn var processSortOrder: ProcessSortOrder?
    @BlackbirdColumn var osType: String?
    @BlackbirdColumn var osVersion: String?
    @BlackbirdColumn var iconData: Data?
    @BlackbirdColumn var containerRuntime: String?
    @BlackbirdColumn var isMacOS: Bool?

    enum ProcessSortOrder: String, RawRepresentable, BlackbirdStringEnum {
        typealias RawValue = String
        
        case pid, command, user, memory, cpu
        case pidReversed, commandReversed, userReversed, memoryReversed, cpuReversed
    }
    var credential: Credential? {
        keychain().getCredential(for: credentialKey)
    }
    var containers: [Container] {
        get async throws {
            try await Container.read(from: SharedDatabase.db, matching: \.$serverId == id)
        }
    }

    init(credentialKey: String) {
        self.credentialKey = credentialKey
        self.id = credentialKey
        self.isConnected = false
    }
}

extension Server {
    var server: Server? {
        get async throws {
            try await Server.read(from: SharedDatabase.db, id: id)
        }
    }
    var db : Blackbird.Database {
        SharedDatabase.db
    }

    func connect() async throws {
        let _ = try await execute("echo hello")
        var server = self
        server.isConnected = true
        try await server.write(to: db)

        guard let credential else { return }

        await SSHClientActor.shared.onDisconnect(of: credential) {
            Task{
                var server = try await self.server
                server?.isConnected = false
                try? await server?.write(to: db)
            }
        }
    }

    func disconnect() async throws {
        guard let credential = try await server?.credential else { return }
        try await SSHClientActor.shared.disconnect(credential)
    }

    func fetchServerStats() async {
        // Detect OS information and container runtime first
        await detectOSInfo()
        await detectContainerRuntime()

        // Check if this is a macOS server
        let isMacOS = try? await server?.isMacOS ?? false

        // Use OS-specific commands
        async let cpuUsage: Double? = isMacOS == true ?
            fetchMetric(command: "ps -A -o %cpu | awk '{s+=$1} END {print s/100}'") :
            fetchMetric(command: "sar -u 1 3 | grep 'Average' | awk '{print (100 - $8) / 100}'")

        async let memoryUsage: Double? = isMacOS == true ?
            fetchMetric(command: """
vm_stat | awk '
/Pages active/ {active=$3}
/Pages inactive/ {inactive=$3}
/Pages speculative/ {speculative=$3}
/Pages wired/ {wired=$3}
/Pages free/ {free=$3}
END {
    gsub(/\\./, "", active); gsub(/\\./, "", inactive); gsub(/\\./, "", speculative);
    gsub(/\\./, "", wired); gsub(/\\./, "", free);
    used = (active + inactive + speculative + wired) * 4096;
    total = (active + inactive + speculative + wired + free) * 4096;
    print used/total
}'
""") :
            fetchMetric(command: "free | grep Mem | awk '{print $3/$2}'")

        async let diskUsage: Double? = isMacOS == true ?
            fetchMetric(command: "df -k / | awk 'NR==2 {print $5 / 100}'") :
            fetchMetric(command: "df / | grep / | awk '{ print $5 / 100 }'")

        async let networkUpstream: Double? = isMacOS == true ?
            nil : // Network stats are complex on macOS, skip for now
            fetchMetric(command: """
iface=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}'); \
sar -n DEV 1 2 | grep Average | grep $iface | awk '{print $5 * 1024}'
""")

        async let networkDownstream: Double? = isMacOS == true ?
            nil : // Network stats are complex on macOS, skip for now
            fetchMetric(command: """
iface=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}'); \
sar -n DEV 1 2 | grep Average | grep $iface | awk '{print $6 * 1024}'
""")

        async let swapUsage: Double? = isMacOS == true ?
            fetchMetric(command: """
sysctl vm.swapusage | awk '{
    for(i=1;i<=NF;i++) {
        if($i ~ /used/) {
            split($(i+2), a, "M");
            used=a[1];
        }
        if($i ~ /total/) {
            split($(i+2), b, "M");
            total=b[1];
        }
    }
    if(total > 0) print used/total; else print 0
}'
""") :
            fetchMetric(command: "free | grep Swap | awk '{print $3/$2}'")

        async let ioWait: Double? = isMacOS == true ?
            nil : // IO wait not readily available on macOS
            fetchMetric(command: "sar -u 1 3 | grep 'Average' | awk '{print $5 / 100}'")

        async let stealTime: Double? = isMacOS == true ?
            nil : // Steal time is a virtualization metric, not applicable to macOS
            fetchMetric(command: "sar -u 1 3 | grep 'Average' | awk '{print $6 / 100}'")

        async let systemLoad: Double? = isMacOS == true ?
            fetchMetric(command: "uptime | awk '{print $(NF-2) / 100}'") :
            fetchMetric(command: "uptime | awk '{print $(NF-2) / 100}'")

        async let totalDiskSpace: Double? = isMacOS == true ?
            fetchMetric(command: "df -k / | awk 'NR==2 {print $2 * 1024}'") :
            fetchMetric(command: "df --output=size / | tail -n 1 | awk '{print $1 * 1024}'")

        async let totalMemory: Double? = isMacOS == true ?
            fetchMetric(command: "sysctl -n hw.memsize") :
            fetchMetric(command: "free | grep Mem | awk '{print $2 * 1024}'")

        async let cpuCores: Double? = isMacOS == true ?
            fetchMetric(command: "sysctl -n hw.ncpu") :
            fetchMetric(command: "nproc")

        var newUptime = Date?.none
        if isMacOS == true {
            // macOS: use sysctl kern.boottime
            let uptimeCommand = "sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//'"
            let uptimeOutput = try? await execute(uptimeCommand)
            if let uptimeOutput,
               let timestamp = Double(uptimeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                newUptime = Date(timeIntervalSince1970: timestamp)
            }
        } else {
            // Linux: use uptime -s
            let uptimeCommand = "date +%s -d \"$(uptime -s)\""
            let uptimeOutput = try? await execute(uptimeCommand)
            if let uptimeOutput,
               let timestamp = Double(uptimeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                newUptime = Date(timeIntervalSince1970: timestamp)
            }
        }

        // Await all async lets before proceeding
        let (cpu, memory, disk, networkUpstreamResult, networkDownstreamResult, swap, io, steal, load, diskSpace, memTotal, cores) =
        await (cpuUsage, memoryUsage, diskUsage, networkUpstream, networkDownstream, swapUsage, ioWait, stealTime, systemLoad, totalDiskSpace, totalMemory, cpuCores)

        guard cpu != nil || memory != nil || disk != nil ||
        networkUpstreamResult != nil || networkDownstreamResult != nil ||
        swap != nil || io != nil || steal != nil ||
        load != nil || diskSpace != nil || memTotal != nil || cores != nil else {
            return
        }

        if var server = try? await server {
            server.cpuUsage = cpu ?? server.cpuUsage
            server.memoryUsage = memory ?? server.memoryUsage
            server.diskUsage = disk ?? server.diskUsage
            server.networkUpstream = networkUpstreamResult ?? server.networkUpstream
            server.networkDownstream = networkDownstreamResult ?? server.networkDownstream
            server.swapUsage = swap ?? server.swapUsage
            server.ioWait = io ?? server.ioWait
            server.stealTime = steal ?? server.stealTime
            server.systemLoad = load ?? server.systemLoad
            server.totalDiskSpace = diskSpace ?? server.totalDiskSpace
            server.totalMemory = memTotal ?? server.totalMemory
            server.cpuCores = cores == nil ? server.cpuCores : Int(cores!)
            server.lastUpdate = .now
            if let newUptime{
                server.uptime = newUptime
            }
            try? await server.write(to: db)
        }
    }

    func fetchDockerStats() async {
        do {
            let output = try await execute("""
    docker stats --no-stream --format "{{.ID}} {{.Name}} {{.CPUPerc}} {{.MemUsage}}" | while read id name cpu mem; do
        status=$(docker ps --filter "id=$id" --format "{{.Status}}")
        
        # Fetch total memory for the container using docker inspect
        totalMem=$(docker inspect --format '{{.HostConfig.Memory}}' $id)

        # Check if totalMem is empty or zero, fallback to a default value
        if [ -z "$totalMem" ] || [ "$totalMem" -eq 0 ]; then
            totalMem="N/A"
        fi
        
        # Output the stats with both used memory and total memory
        echo "$id $name $cpu $mem $status"
    done
""")
            let stopped = try await execute("""
    docker ps -a --filter "status=exited" --format "{{.ID}} {{.Names}} {{.Status}}" | awk '{id=$1; name=$2; status=$3; cpu="0"; mem="0 / 0"; totalMem="N/A"; print id, name, cpu, mem, status}'
""")
            let newContainers = try parseDockerStats(from: "\(output)\n\(stopped)")


            let containers = try await self.containers
            for newContainer in newContainers {
                if var existingContainer = try await Container.read(from: db, id: newContainer.id) {
                    existingContainer.name = newContainer.name
                    existingContainer.status = newContainer.status
                    existingContainer.cpuUsage = newContainer.cpuUsage
                    existingContainer.memoryUsage = newContainer.memoryUsage
                    try await existingContainer.write(to: db)
                } else {
                    let container = Container(id: newContainer.id, name: newContainer.name, status: newContainer.status, cpuUsage: newContainer.cpuUsage, memoryUsage: newContainer.memoryUsage, serverId: id)
                    try await container.write(to: db)
                }
            }
            await fetchProcesses()
            
            // Remove containers that no longer exist on the server
            // Only remove if we can confirm they don't exist with multiple checks
            for container in containers.filter({ container in
                !newContainers.contains(where: { $0.id == container.id })
            }) {
                // Use multiple verification methods to be absolutely sure
                var containerExists = false
                var verificationFailed = false
                
                // Method 1: Check by ID
                let checkByIdCommand = "docker ps -a --filter \"id=\(container.id)\" --format \"{{.ID}}\" 2>/dev/null && echo 'CMD_SUCCESS' || echo 'CMD_FAILED'"
                if let idOutput = try? await execute(checkByIdCommand) {
                    let lines = idOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if lines.contains("CMD_SUCCESS") {
                        // Command executed successfully
                        if lines.contains(container.id) {
                            containerExists = true
                            print("✓ Container \(container.name) (\(container.id)) confirmed by ID check")
                        }
                    } else if lines.contains("CMD_FAILED") {
                        // Command failed (Docker not available, etc.)
                        verificationFailed = true
                        print("⚠️ Docker ID check failed for \(container.name) (\(container.id)) - keeping container")
                    } else if lines.isEmpty || lines.allSatisfy({ $0.isEmpty }) {
                        // Empty response - could be network issue, be conservative
                        verificationFailed = true
                        print("⚠️ Empty response for container ID check \(container.name) (\(container.id)) - keeping container")
                    }
                } else {
                    verificationFailed = true
                    print("⚠️ Could not execute ID check for container \(container.name) (\(container.id)) - keeping container")
                }
                
                // Method 2: Check by name as backup (only if ID check succeeded)
                if !verificationFailed && !containerExists {
                    let checkByNameCommand = "docker ps -a --filter \"name=^/\(container.name)$\" --format \"{{.Names}}\" 2>/dev/null && echo 'CMD_SUCCESS' || echo 'CMD_FAILED'"
                    if let nameOutput = try? await execute(checkByNameCommand) {
                        let lines = nameOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if lines.contains("CMD_SUCCESS") {
                            if lines.contains(container.name) {
                                containerExists = true
                                print("✓ Container \(container.name) (\(container.id)) confirmed by name check")
                            }
                        } else if lines.contains("CMD_FAILED") || lines.isEmpty || lines.allSatisfy({ $0.isEmpty }) {
                            verificationFailed = true
                            print("⚠️ Docker name check inconclusive for \(container.name) (\(container.id)) - keeping container")
                        }
                    } else {
                        verificationFailed = true
                        print("⚠️ Could not execute name check for container \(container.name) (\(container.id)) - keeping container")
                    }
                }
                
                // Only delete if we're absolutely certain the container doesn't exist
                if !verificationFailed && !containerExists {
                    try await container.delete(from: db)
                    print("🗑️ Deleted confirmed non-existent container: \(container.name) (\(container.id))")
                } else if verificationFailed {
                    print("🔒 Keeping container \(container.name) (\(container.id)) due to verification failure")
                } else {
                    print("💾 Keeping existing container \(container.name) (\(container.id))")
                }
            }
        } catch {
        }
    }
    
    func clearCachedContainers() async throws {
        try await Container.delete(from: db, matching: \.$serverId == id)
    }

    private func fetchMetric(command: String) async -> Double? {
        do {
            let output = try await execute(command)
            return try parseSingleValue(from: output, command: command)
        } catch {
            return nil
        }
    }

    private func parseSingleValue(from output: String, command: String = "") throws(ServerError) -> Double {
        let lines = output.split(whereSeparator: \.isNewline)
        for line in lines {
            let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            if let value = Double(cleanedLine) {
                return value
            }
        }
        throw ServerError.invalidStatsOutput("\(command) failed: \(output)")
    }

    private func parseDockerStats(from output: String) throws(ServerError) -> [(id: String, name: String, status: String, cpuUsage: Double, memoryUsage: Double)] {
        do {
            let lines = output.split(whereSeparator: \.isNewline)
            return try lines.map { line in
                var parts = line.split(separator: " ", omittingEmptySubsequences: true)

                // Ensure there are enough parts to parse
                guard parts.count >= 6 else {
                    throw ServerError.invalidStatsOutput("Malformed or incomplete container info: \(line)")
                }

                let id = String(parts[0])
                let name = String(parts[1])
                let cpuUsageString = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
                guard let cpuUsage = Double(cpuUsageString) else {
                    throw ServerError.invalidStatsOutput("Invalid CPU usage in line: \(line)")
                }

                // Memory usage parsing
                let memoryUsage = String(parts[3])

                let totalMemString = String(parts[5])


                let usedMemoryBytes = try parseMemoryUsage(memoryUsage)
                let totalMemoryBytes = try parseMemoryUsage(totalMemString)

                let memoryUsagePercentage = totalMemoryBytes.isZero ? 0 : (usedMemoryBytes / totalMemoryBytes)

                print(parts)
                parts.removeFirst(6)

                let status = String(parts.joined(separator: " "))

                return (id: id, name: name, status: status, cpuUsage: cpuUsage / 100, memoryUsage: memoryUsagePercentage)
            }
        } catch {
            throw error as! ServerError
        }
    }


    private func parseUsage(from usage: Substring) throws(ServerError) -> Double {
        if let value = Double(usage.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")) {
            return value
        }
        throw ServerError.invalidStatsOutput(String(usage))
    }


    private func parseMemoryUsage(_ memoryString: String) throws(ServerError) -> Double {
        let units = ["MiB": 1_048_576.0, "KiB": 1_024.0, "GiB": 1_073_741_824.0, "B": 1.0]

        // Loop over the units to check which one is present
        if memoryString == "0" || (memoryString.localizedCaseInsensitiveContains("N/A")) {
            return 0
        }
        for (unit, multiplier) in units {
            if memoryString.contains(unit) {
                let numericValue = memoryString.replacingOccurrences(of: unit, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(numericValue) {
                    return value * multiplier
                }
            }
        }
        // Handle the case where no valid unit is found
        throw .invalidStatsOutput("Couldn't parse memory usage from: \(memoryString)")
    }

    func execute(_ command: String) async throws -> String {
        if let credential {
            return try await SSHClientActor.shared.execute(command, on: credential)
        } else {return ""}
    }
    
    private func detectContainerRuntime() async {
        var runtime: String? = nil

        // Method 1: Check docker info output for OrbStack
        if let dockerInfo = try? await execute("docker info 2>/dev/null | grep -i 'operating system\\|orbstack' || true") {
            let trimmed = dockerInfo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.lowercased().contains("orbstack") {
                runtime = "orbstack"
            }
        }

        // Method 2: Check if orbstack command exists
        if runtime == nil {
            if let orbctlPath = try? await execute("which orbctl 2>/dev/null || true") {
                let trimmed = orbctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !trimmed.contains("not found") {
                    runtime = "orbstack"
                }
            }
        }

        // Method 3: Check Docker context
        if runtime == nil {
            if let contextOutput = try? await execute("docker context show 2>/dev/null || true") {
                let trimmed = contextOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.lowercased().contains("orbstack") {
                    runtime = "orbstack"
                }
            }
        }

        // Method 4: Check docker version output
        if runtime == nil {
            if let versionOutput = try? await execute("docker version 2>/dev/null | grep -i orbstack || true") {
                let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    runtime = "orbstack"
                }
            }
        }

        // Default to docker if we can execute docker commands but didn't detect OrbStack
        if runtime == nil {
            if let dockerVersion = try? await execute("docker --version 2>/dev/null || true") {
                let trimmed = dockerVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.lowercased().contains("docker") {
                    runtime = "docker"
                }
            }
        }

        // Update server with container runtime if detected
        if let runtime = runtime, var server = try? await server {
            server.containerRuntime = runtime
            try? await server.write(to: db)
        }
    }

    private func detectOSInfo() async {
        // Try multiple methods to detect OS
        var osType: String?
        var osVersion: String?
        var isMacOS = false

        // Method 0: Check if it's macOS first using uname
        if let unameOutput = try? await execute("uname -s") {
            let unameValue = unameOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if unameValue.lowercased() == "darwin" {
                isMacOS = true
                osType = "macos"

                // Get macOS version
                if let versionOutput = try? await execute("sw_vers -productVersion") {
                    osVersion = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Method 1: /etc/os-release (most modern Linux distributions)
        if !isMacOS, let osReleaseOutput = try? await execute("cat /etc/os-release 2>/dev/null") {
            osType = parseOSFromRelease(osReleaseOutput)
            osVersion = parseVersionFromRelease(osReleaseOutput)
        }

        // Method 2: lsb_release (if available)
        if osType == nil && !isMacOS, let lsbOutput = try? await execute("lsb_release -d 2>/dev/null | cut -f2") {
            osType = parseOSFromLSB(lsbOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Method 3: Check specific files for older systems
        if osType == nil && !isMacOS {
            if let _ = try? await execute("test -f /etc/redhat-release && echo 'exists'") {
                if let content = try? await execute("cat /etc/redhat-release") {
                    osType = parseOSFromRedHat(content)
                }
            } else if let _ = try? await execute("test -f /etc/debian_version && echo 'exists'") {
                osType = "debian"
            }
        }

        // Update server with OS info if detected
        if let osType = osType, var server = try? await server {
            server.osType = osType
            server.osVersion = osVersion
            server.isMacOS = isMacOS
            try? await server.write(to: db)

            // Fetch icon if we don't have one
            if server.iconData == nil {
                await fetchOSIcon(for: osType)
            }
        }
    }
    
    private func parseOSFromRelease(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("ID=") {
                let id = line.replacingOccurrences(of: "ID=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return id.lowercased()
            }
        }
        
        // Fallback to NAME field
        for line in lines {
            if line.hasPrefix("NAME=") {
                let name = line.replacingOccurrences(of: "NAME=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return parseOSFromName(name)
            }
        }
        return nil
    }
    
    private func parseVersionFromRelease(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("VERSION_ID=") {
                return line.replacingOccurrences(of: "VERSION_ID=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }
    
    private func parseOSFromLSB(_ content: String) -> String? {
        return parseOSFromName(content)
    }
    
    private func parseOSFromRedHat(_ content: String) -> String? {
        let lower = content.lowercased()
        if lower.contains("centos") { return "centos" }
        if lower.contains("red hat") || lower.contains("rhel") { return "rhel" }
        if lower.contains("fedora") { return "fedora" }
        return "rhel" // Default for Red Hat family
    }
    
    private func parseOSFromName(_ name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("ubuntu") { return "ubuntu" }
        if lower.contains("debian") { return "debian" }
        if lower.contains("centos") { return "centos" }
        if lower.contains("red hat") || lower.contains("rhel") { return "rhel" }
        if lower.contains("fedora") { return "fedora" }
        if lower.contains("suse") || lower.contains("opensuse") { return "opensuse" }
        if lower.contains("arch") { return "arch" }
        if lower.contains("alpine") { return "alpine" }
        if lower.contains("mint") { return "mint" }
        if lower.contains("kali") { return "kali" }
        if lower.contains("manjaro") { return "manjaro" }
        return nil
    }
    
    private func fetchOSIcon(for osType: String) async {
        // Map OS types to icon URLs
        let iconURLs: [String: String] = [
            "ubuntu": "https://assets.ubuntu.com/v1/29985a98-ubuntu-logo32.png",
            "debian": "https://www.debian.org/logos/openlogo-nd-25.png",
            "centos": "https://wiki.centos.org/ArtWork/Brand/Logo?action=AttachFile&do=get&target=centos-logo-light.png",
            "rhel": "https://www.redhat.com/cms/managed-files/styles/wysiwyg_full_width/s3/Logo-Red_Hat-A-Color-RGB.png",
            "fedora": "https://fedoraproject.org/static/images/fedora-logotext.png",
            "opensuse": "https://en.opensuse.org/images/c/cd/Button-colour.png",
            "arch": "https://archlinux.org/static/logos/archlinux-logo-dark-90dpi.ebdee92a15b3.png",
            "alpine": "https://alpinelinux.org/alpine-logo.png",
            "mint": "https://www.linuxmint.com/img/logo.png",
            "kali": "https://www.kali.org/images/kali-logo.png",
            "manjaro": "https://manjaro.org/img/manjaro-logo.svg"
        ]
        
        guard let urlString = iconURLs[osType],
              let url = URL(string: urlString) else {
            print("No icon URL found for OS: \(osType)")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Verify it's a valid image
            if data.count > 0 && (data.starts(with: [0x89, 0x50, 0x4E, 0x47]) || // PNG
                                  data.starts(with: [0xFF, 0xD8, 0xFF]) || // JPEG
                                  data.starts(with: [0x47, 0x49, 0x46])) { // GIF
                
                if var server = try? await server {
                    server.iconData = data
                    try? await server.write(to: db)
                    print("Successfully downloaded icon for \(osType)")
                }
            }
        } catch {
            print("Failed to download icon for \(osType): \(error)")
        }
    }
    
    /// Get the appropriate SF Symbol name for the OS
    var osIconName: String {
        guard let osType = osType else { return "server.rack" }

        switch osType {
        case "macos": return "apple.logo"
        case "ubuntu": return "u.circle.fill"
        case "debian": return "d.circle.fill"
        case "centos": return "c.circle.fill"
        case "rhel": return "r.circle.fill"
        case "fedora": return "f.circle.fill"
        case "opensuse": return "s.circle.fill"
        case "arch": return "a.circle.fill"
        case "alpine": return "mountain.2.fill"
        case "mint": return "m.circle.fill"
        case "kali": return "k.circle.fill"
        case "manjaro": return "circle.fill"
        default: return "server.rack"
        }
    }
    
    /// Get the appropriate color for the OS
    var osIconColor: String {
        guard let osType = osType else { return "blue" }

        switch osType {
        case "macos": return "gray"
        case "ubuntu": return "orange"
        case "debian": return "red"
        case "centos": return "purple"
        case "rhel": return "red"
        case "fedora": return "blue"
        case "opensuse": return "green"
        case "arch": return "blue"
        case "alpine": return "blue"
        case "mint": return "green"
        case "kali": return "purple"
        case "manjaro": return "green"
        default: return "blue"
        }
    }

    /// Get the appropriate SF Symbol name for the container runtime
    var containerRuntimeIcon: String {
        guard let runtime = containerRuntime else { return "shippingbox" }

        switch runtime.lowercased() {
        case "orbstack": return "square.stack.3d.up"
        case "docker": return "shippingbox"
        default: return "shippingbox"
        }
    }

    /// Get the display name for the container runtime
    var containerRuntimeDisplayName: String {
        guard let runtime = containerRuntime else { return "Container Runtime" }

        switch runtime.lowercased() {
        case "orbstack": return "OrbStack"
        case "docker": return "Docker"
        default: return runtime.capitalized
        }
    }
}

import Foundation
import ServiceManagement

public final class LaunchAtLoginService {
    public init() {}

    public func sync(enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .enabled), (false, .notRegistered):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }
    }
}

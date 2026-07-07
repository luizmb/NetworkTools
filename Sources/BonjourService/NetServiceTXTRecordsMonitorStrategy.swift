// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Controls whether resolution continues watching for TXT record changes
/// after the initial resolution.
///
/// Pass `.keepMonitoringTXTUpdates` when you need live TXT record updates (e.g. dynamic
/// metadata like device capability flags). Use `.doNotMonitorTXTUpdates` for a one-shot
/// resolve and cancel.
public enum NetServiceTXTRecordsMonitorStrategy: Equatable {
    /// Keep monitoring and emit `didUpdateTXTRecord` events as the TXT record changes.
    case keepMonitoringTXTUpdates
    /// Resolve once and stop; ignore any subsequent TXT record changes.
    case doNotMonitorTXTUpdates
}

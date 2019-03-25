//
//  PodDoseProgressEstimator.swift
//  OmniKit
//
//  Created by Pete Schwamb on 3/12/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit

class PodDoseProgressEstimator: DoseProgressEstimator {

    public let dose: DoseEntry

    private var observers = WeakSet<DoseProgressObserver>()

    private var lock = os_unfair_lock()

    private var timer: Timer?

    var progress: DoseProgress {
        let elapsed = -dose.startDate.timeIntervalSinceNow
        let duration = dose.endDate.timeIntervalSince(dose.startDate)
        let percentComplete = min(elapsed / duration, 1)
        let delivered = OmnipodPumpManager.roundToDeliveryIncrement(units: percentComplete * dose.units)
        return DoseProgress(deliveredUnits: delivered, percentComplete: percentComplete)
    }

    init(dose: DoseEntry) {
        self.dose = dose
    }

    func addObserver(_ observer: DoseProgressObserver) {
        os_unfair_lock_lock(&lock)
        defer {
            os_unfair_lock_unlock(&lock)
        }
        let firstObserver = observers.isEmpty
        observers.insert(observer)
        if firstObserver {
            start(on: RunLoop.main)
        }
    }

    func removeObserver(_ observer: DoseProgressObserver) {
        os_unfair_lock_lock(&lock)
        defer {
            os_unfair_lock_unlock(&lock)
        }
        observers.remove(observer)
        if observers.isEmpty {
            stop()
        }
    }

    private func notify() {
        os_unfair_lock_lock(&lock)
        let observersCopy = observers
        os_unfair_lock_unlock(&lock)

        for observer in observersCopy {
            observer.doseProgressEstimatorHasNewEstimate(self)
        }
    }


    func start(on runLoop: RunLoop) {
        let timeSinceStart = dose.startDate.timeIntervalSinceNow
        let timeBetweenPulses: TimeInterval
        switch dose.type {
        case .bolus:
            timeBetweenPulses = Pod.pulseSize / Pod.bolusDeliveryRate
        case .basal, .tempBasal:
            timeBetweenPulses = Pod.pulseSize / dose.unitsPerHour
        default:
            fatalError("Can only estimate progress on basal rates or boluses.")
        }
        let delayUntilNextPulse = timeBetweenPulses - timeSinceStart.remainder(dividingBy: timeBetweenPulses)
        let timer = Timer(fire: Date() + delayUntilNextPulse, interval: timeBetweenPulses, repeats: true) { [weak self] _  in
            if let self = self {
                self.notify()
            }
        }
        runLoop.add(timer, forMode: .default)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
    }


}

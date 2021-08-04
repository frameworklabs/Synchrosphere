// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Pappe
import Dispatch // for DispatchSource

/// Provides activities to pause the current trail for some time.
final class TimerController {
    
    private let context: ControllerContext
    private var timer: DispatchSourceTimer?

    init(context: ControllerContext) {
        self.context = context
    }

    func makeModule(imports: [Module.Import]) -> Module {
        Module(imports: imports) { name in
            
            activity (Syncs.WaitTicks, [name.ticks]) { val in
                exec { val.start = self.context.clock.counter }
                `await` { self.context.clock.tick(downBy: val.ticks, from: val.start) }
            }

            activity (Syncs.WaitMilliseconds, [name.millis]) { val in
                exec { val.ticks = max(1, val.millis * self.context.config.tickFrequency / 1000) }
                run (Syncs.WaitTicks, [val.ticks])
            }
            
            activity (Syncs.WaitSeconds, [name.secs]) { val in
                run (Syncs.WaitMilliseconds, [val.secs * 1000])
            }
        }
    }
    
    func startTimer() {
        assert(timer == nil)
                
        timer = DispatchSource.makeTimerSource(queue: context.config.queue ?? DispatchQueue.main)
        let period = 1.0 / Double(context.config.tickFrequency)
        timer?.setEventHandler { [unowned self] in tick() }
        timer?.schedule(deadline: .now() + period, repeating: period, leeway: .nanoseconds(100))
        timer?.activate()
        
        context.isTimerRunning = true
    }
    
    func stopTimer() {
        context.isTimerRunning = false
        
        timer?.cancel()
        timer = nil
    }
    
    /// - Note: not private to allow testing.
    func tick() {
        context.clock.tick = true
        context.clock.counter &+= 1
        context.tick()
        context.clock.tick = false
    }
}

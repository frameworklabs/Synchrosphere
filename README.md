# Synchrosphere

A Swift framework to control Sphero robots in a synchronous reactive style.

## About

[Sphero](https://sphero.com) robots can be wirelessly controlled and observed from an external computer by sending and receiving Bluetooth messges. Synchrosphere provides an API to do so from a Mac or iOS device in a synchronous reactive manner via the embedded imperative synchronous Swift DSL [Pappe](https://github.com/frameworklabs/Pappe). This programming style is especially helpful in robotics as it simplifies the coding of concurrent tasks in a safe manner, due to deterministic synchronization between tasks. This quality also enables sound preemption, which is another important concept in robotics where preconditions needs to be checked and handled constantly.

In addition, this project shows how synchronous reactive programming can help to turn delegate based callback APIs - as common with Apple frameworks - back into structured code to simplify their usage.

## Usage

Synchrosphere tries to make it simple to control Sphero robots. Currently only Sphero Mini is supported.

Start by importing this package into your project. Its dependency to Pappe will be resolved implicitly.

Next, create a `SyncsController` in your code and assign it to an instance variable of your App - or some other place which lives long enough. 

When creating a `SyncsController` you provide a configuration of type `SyncsControllerConfig` and a closure which will build and return the activities to control the robot. One returned activity must be named "Main" and will be called as entrypoint once a robot conforming to the configuration was found and activated (see next step). When control returns from this main activity the robot is deactivated again.

Finally, call `start()` on the created controller to start the scanning, activation and control of the robot. If you want to emergency-stop the robot (or stop a lengthy scanning process ) call `stop()` any time.

For a usage of the Synchrosphere framework, see also the accompanying project [SynchrosphereDemo](https://github.com/frameworklabs/SynchrosphereDemo) which provides a UI application to select different robot control demos.

## Example

Let's create a Sphero Mini controller which moves the robot in a rectangular loop back to its starting spot while blinking green as long as it moves.

```Swift
ctrl = SyncsEngine().makeController { name, ctx in
    activity (name.Main, []) { val in
        cobegin {
            strong {
                run (Syncs.RollForSeconds, [SyncsSpeed(100), SyncsHeading(0), SyncsDir.forward, 3])
                run (Syncs.RollForSeconds, [SyncsSpeed(100), SyncsHeading(90), SyncsDir.forward, 2])
                run (Syncs.RollForSeconds, [SyncsSpeed(100), SyncsHeading(180), SyncsDir.forward, 3])
                run (Syncs.RollForSeconds, [SyncsSpeed(100), SyncsHeading(270), SyncsDir.forward, 2])
            }
            weak {
                `repeat` {
                    run (Syncs.SetMainLED, [SyncsColor.green])
                    run (Syncs.WaitMilliseconds, [500])
                    run (Syncs.SetMainLED, [SyncsColor.black])
                    run (Syncs.WaitMilliseconds, [500])
                }
            }
        }
    }
}

ctrl.start()
```
The controller is created with a single activity named "Main". The `cobegin` construct creates two concurrent trails (threads) with the first one responsible for moving the robot and the second one responsible for blinking. The `cobegin` construct should stop once the first trail has finished (but not earlier) - this is why the first trail is marked `strong`. The blinking code in the second trail should stop as soon as the move has finished - thus it is marked as `weak`.

Within the trails, built-in activities to roll the robot, set its LED and wait for some time are called via the `run` statements. See the header docs for all provided activities and their parameters.

Finally, the controller is started explicitly and runs until it finishes. Note that `start()` is asynchronous and returns before the robot control code has finished. This is also why the created controller variable `ctrl` needs to be assigned to a variable with a long enough lifetime (i.e. probably not a local variable).

## Limitations

- Only Sphero Mini robots are supported right now.
- Only a minimal API to control the robots is offered right now.

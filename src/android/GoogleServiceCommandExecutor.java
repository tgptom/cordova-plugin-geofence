package com.cowbell.cordova.geofence;

import java.util.LinkedList;
import java.util.Queue;

public class GoogleServiceCommandExecutor implements IGoogleServiceCommandListener {
    private Queue<AbstractGoogleServiceCommand> commandsToExecute;
    private boolean isExecuting = false;
    private final Object lock = new Object();

    public GoogleServiceCommandExecutor() {
        commandsToExecute = new LinkedList<AbstractGoogleServiceCommand>();
    }

    public void QueueToExecute(AbstractGoogleServiceCommand command) {
        synchronized (lock) {
            commandsToExecute.add(command);
            if (!isExecuting) {
                ExecuteNextLocked();
            }
        }
    }

    private void ExecuteNextLocked() {
        if (commandsToExecute.isEmpty()) return;
        isExecuting = true;
        AbstractGoogleServiceCommand command = commandsToExecute.poll();
        command.addListener(this);
        command.Execute();
    }

    @Override
    public void onCommandExecuted(Object error) {
        synchronized (lock) {
            isExecuting = false;
            ExecuteNextLocked();
        }
    }
}

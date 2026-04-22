// src/game/EventBus.js
import { EventEmitter } from 'events';

class EventBus extends EventEmitter {}

const eventBus = new EventBus();

export const on   = (event, listener) => eventBus.on(event, listener);
export const off  = (event, listener) => eventBus.off(event, listener);
export const emit = (event, ...args)  => eventBus.emit(event, ...args);
export const once = (event, listener) => eventBus.once(event, listener);

export default eventBus;

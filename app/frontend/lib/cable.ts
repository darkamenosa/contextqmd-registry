import * as ActionCable from "@rails/actioncable"

let consumer: ActionCable.Consumer | null = null

export function getConsumer() {
  if (!consumer) {
    consumer = ActionCable.createConsumer("/cable")
  }
  return consumer
}

export type Subscription = ActionCable.Subscription

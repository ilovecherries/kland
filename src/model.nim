import options
import norm/[model, pragmas]
import times
import system

type
  Post* = ref object of Model
    content*: string
    timestamp*: DateTime
    author*: Option[string]
    threadId*: int64
    trip*: Option[string]
    image*: Option[string]
    # TODO: we need to also add a type for images

  Thread* = ref object of Model
    title* {.unique.}: string


func newPost*(content = "",
              threadId: int64 = 1;
              author = none string;
              trip = none string;
              image = none string;
              timestamp = now()): Post =
  Post(
    content: content,
    threadId: threadId,
    author: author,
    trip: trip,
    timestamp: timestamp,
    image: image
  )

func newThread*(title = ""): Thread =
  Thread(
    title: title,
  )

import options
import norm/[model]
import times
import system

type
  Post* = ref object of Model
    content*: string
    timestamp*: DateTime
    author*: Option[string]
    threadId*: int64
    # TODO: we need to also add a type for images

  Thread* = ref object of Model
    title*: string


func newPost*(content = "",
              threadId: int64 = 1;
              author = none string;
              timestamp = now()): Post =
  Post(
    content: content,
    author: author,
    timestamp: timestamp
  )

func newThread*(title = ""): Thread =
  Thread(
    title: title,
  )

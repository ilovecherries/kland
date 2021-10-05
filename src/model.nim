import options
import norm/[model]
import times

type
  Post* = ref object of Model
    content*: string
    timestamp*: DateTime
    author*: Option[string]
    threadId*: int
    # TODO: we need to also add a type for images
    
  Thread* = ref object of Model
    title*: string


func newPost*(content = "",
              threadId = 0,
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

import options
import norm/[model]
import times
import json
import system

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

# ok i want to make a macro so that i dont have to do hasKey len == 0
# whatever garbage
# template

type ModelCreateError* = object of ValueError

proc newPostFromJSON*(threadId: int, data: JsonNode): Post =
  # need to throw errors rather than just directly do http
  # shit
  if not data.hasKey("content"):
    raise newException(ModelCreateError, "The content in the post is missing.")
  let content = data["content"].getStr()
  if content.len == 0:
    raise newException(ModelCreateError, "The content in the post is empty.")
    
  let author: Option[string] =
    if data.hasKey("author"): some(data["author"].getStr()) else: none(string)

  newPost(content, threadId, author)

  
func newThread*(title = ""): Thread =
  Thread(
    title: title,
  )

proc newThreadFromJSON*(data: JsonNode): (Thread, Post) =
  if not data.hasKey("post"):
    raise newException(ModelCreateError, "The initial post for the thread is missing")
  let postData = parseJson(data["post"].getStr())
  # noooo this is so evil..., but how am i supposed to know if the post is valid,
  let post = newPostFromJSON(-1, postData)

  if not data.hasKey("title"):
    raise newException(ModelCreateError, "The title of the thread is missing.")
  let title = data["title"].getStr()
  if title.len == 0:
    raise newException(ModelCreateError, "The title of the thread is empty.")
  let thread = newThread(title)

  return (thread, post)

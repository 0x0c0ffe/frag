import
  tables

import
  freetype,
  glm,
  opengl,
  sdl2 as sdl

import
  ../graphics/shader

type
  AssetType* = enum
    Texture, VectorFont

  Character* = object
    textureID*: GLuint
    size*: Vec2i
    bearing*: Vec2i
    advance*: GLuint

  Asset* = object
    case assetType*: AssetType
    of Texture:
      handle*: GLuint
      filename*: string
      data*: sdl.SurfacePtr
      width*: int
      height*: int
    of VectorFont:
      fontFace*: Face
      characters*: Table[GLchar, Character]
      vao*, vbo*: GLuint
      shaderProgram*: ShaderProgram

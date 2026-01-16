namespace Sedulous.Shaders;

//#define NEW_SHADER_LIB

#if NEW_SHADER_LIB
typealias ShaderLibrary = NewShaderSystem;
#else
typealias ShaderLibrary = OldShaderSystem;
#endif

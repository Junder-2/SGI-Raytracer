using UnityEngine;
using UnityEditor;
using UnityEngine.Rendering;

public class DXRShaderEditor : ShaderGUI
{
    private static readonly int SourceBlend = Shader.PropertyToID("_SourceBlend");
    private static readonly int DestBlend = Shader.PropertyToID("_DestBlend");
    private static readonly int ZWrite = Shader.PropertyToID("_ZWrite");
    private static readonly int NormalMap = Shader.PropertyToID("_NormalMap");
    private static readonly int NormalStrength = Shader.PropertyToID("_NormalStrength");
    private static readonly int Reflection = Shader.PropertyToID("_Reflection");
    private static readonly int Refraction = Shader.PropertyToID("_Refraction");
    private static readonly int UseAlpha = Shader.PropertyToID("_UseAlpha");
    private static readonly int AlphaClip = Shader.PropertyToID("_AlphaClip");
    private static readonly int CullBackfaces = Shader.PropertyToID("_CullBackfaces");
    private static readonly int Cull = Shader.PropertyToID("_Cull");

    public override void ValidateMaterial(Material material)
    {
        base.ValidateMaterial(material);
        Texture normalMap = material.GetTexture(NormalMap);
        float normalStrength = material.GetFloat(NormalStrength);
        bool useNormal = true;
        if(normalMap == null)
            useNormal = false;
        else if(normalMap.name == "black" || normalStrength == 0)
            useNormal = false;
        
        material.SetKeyword(new LocalKeyword(material.shader, "USE_NORMALMAP"), useNormal);

        float reflect = material.GetFloat(Reflection);
        material.SetKeyword(new LocalKeyword(material.shader, "USE_REFLECTIONS"), reflect != 0);

        float refraction = material.GetFloat(Refraction);
        material.SetKeyword(new LocalKeyword(material.shader, "USE_REFRACTION"), refraction != 0);
        
        UpdateTransparent(material);
    }

    private void UpdateTransparent(Material material)
    {
        bool useAlpha = material.GetFloat(UseAlpha) > 0;
        bool alphaClip = material.GetFloat(AlphaClip) > 0;
        bool culling = material.GetFloat(CullBackfaces) > 0;

        if (culling)
            material.SetInt(Cull, (int)CullMode.Back);
        else
            material.SetInt(Cull, (int)CullMode.Off);
        
        material.SetKeyword(new LocalKeyword(material.shader, "USE_ALPHACLIP"), alphaClip);

        if (useAlpha)
        {
            if (alphaClip)
            {
                material.renderQueue = (int)RenderQueue.AlphaTest;
                material.SetOverrideTag("RenderType", "TransparentCutout");
                
                material.SetInt(SourceBlend, (int)BlendMode.One);
                material.SetInt(DestBlend, (int)BlendMode.Zero);
                material.SetInt(ZWrite, 1);
                
                return;
            }
            
            material.renderQueue = (int)RenderQueue.Transparent;
            material.SetOverrideTag("RenderType", "Transparent");

            material.SetInt(SourceBlend, (int)BlendMode.SrcAlpha);
            material.SetInt(DestBlend, (int)BlendMode.OneMinusSrcAlpha);
            material.SetInt(ZWrite, 0);
            return;
        }
        
        material.renderQueue = (int)RenderQueue.Geometry;
        material.SetOverrideTag("RenderType", "Opaque");
        material.SetInt(SourceBlend, (int)BlendMode.One);
        material.SetInt(DestBlend, (int)BlendMode.Zero);
        material.SetInt(ZWrite, 1);
    }
}

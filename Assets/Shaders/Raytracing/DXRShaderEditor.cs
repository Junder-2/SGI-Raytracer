using UnityEngine;
using UnityEditor;
using UnityEngine.Rendering;

public class DXRShaderEditor : ShaderGUI
{
    public override void ValidateMaterial(Material material)
    {
        base.ValidateMaterial(material);
        Texture normalMap = material.GetTexture("_NormalMap");
        float normalStrength = material.GetFloat("_NormalStrength");
        bool useNormal = true;
        if(normalMap == null)
            useNormal = false;
        else if(normalMap.name == "black" || normalStrength == 0)
            useNormal = false;
        
        material.SetKeyword(new LocalKeyword(material.shader, "USE_NORMALMAP"), useNormal);

        float reflect = material.GetFloat("_Reflection");
        material.SetKeyword(new LocalKeyword(material.shader, "USE_REFLECTIONS"), reflect != 0);

        float refraction = material.GetFloat("_Refraction");
        material.SetKeyword(new LocalKeyword(material.shader, "USE_REFRACTION"), refraction != 0);
        
        UpdateTransparent(material);
    }

    private void UpdateTransparent(Material material)
    {
        bool useAlpha = material.GetFloat("_UseAlpha") > 0;
        bool alphaClip = material.GetFloat("_AlphaClip") > 0;
        bool culling = material.GetFloat("_CullBackfaces") > 0;

        if (culling)
            material.SetInt("_Cull", (int)CullMode.Back);
        else
            material.SetInt("_Cull", (int)CullMode.Off);
        
        material.SetKeyword(new LocalKeyword(material.shader, "USE_ALPHACLIP"), alphaClip);

        if (useAlpha)
        {
            if (alphaClip)
            {
                material.renderQueue = (int)RenderQueue.AlphaTest;
                material.SetOverrideTag("RenderType", "TransparentCutout");
                
                material.SetInt("_SourceBlend", (int)BlendMode.One);
                material.SetInt("_DestBlend", (int)BlendMode.Zero);
                material.SetInt("_ZWrite", 1);
                
                return;
            }
            
            material.renderQueue = (int)RenderQueue.Transparent;
            material.SetOverrideTag("RenderType", "Transparent");

            material.SetInt("_SourceBlend", (int)BlendMode.SrcAlpha);
            material.SetInt("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
            material.SetInt("_ZWrite", 0);
            return;
        }
        
        material.renderQueue = (int)RenderQueue.Geometry;
        material.SetOverrideTag("RenderType", "Opaque");
        material.SetInt("_SourceBlend", (int)BlendMode.One);
        material.SetInt("_DestBlend", (int)BlendMode.Zero);
        material.SetInt("_ZWrite", 1);
    }
}

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
    }
}

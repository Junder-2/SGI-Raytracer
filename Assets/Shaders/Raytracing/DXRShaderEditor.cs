using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.Linq;

public class DXRShaderEditor : ShaderGUI
{
    bool reload = true;

    public override void OnGUI (MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        if(reload)
        {
            Reload(materialEditor, properties);
            reload = false;
        }

        // Custom code that controls the appearance of the Inspector goes here
        Material targetMat = materialEditor.target as Material;
        string[] keyWords = targetMat.shaderKeywords;

        EditorGUI.BeginChangeCheck();

        base.OnGUI (materialEditor, properties);

        MaterialProperty normalMap = FindProperty("_NormalMap", properties);
        MaterialProperty normalStrength = FindProperty("_NormalStrength", properties);
        bool useNormal = true;
        if(normalMap.textureValue == null)
            useNormal = false;
        else if(normalMap.textureValue.name == "black" || normalStrength.floatValue == 0)
            useNormal = false;

        MaterialProperty reflect = FindProperty("_Reflection", properties);
        MaterialProperty reflectOverride = FindProperty("_ReflectionOverride", properties);
        bool useReflect = true;
        if(reflect.floatValue == 0)
            useReflect = false;
        bool useReflectOverride = false;
        if(reflectOverride.floatValue == 1)
            useReflectOverride = true;

        MaterialProperty _useAlpha = FindProperty("_UseAlpha", properties);
        bool useAlpha = false;
        if(_useAlpha.floatValue == 1)
            useAlpha = true;        

        MaterialProperty refraction = FindProperty("_Refraction", properties);
        bool useRefraction = false;
        if(refraction.floatValue != 0)
            useRefraction = true;

        /*MaterialProperty fakeThickness = FindProperty("_FakeThickness", properties);
        bool useThickness = false;
        if(fakeThickness.floatValue != 0)
            useThickness = true; */

        if (EditorGUI.EndChangeCheck())
        {
            // if the checkbox is changed, reset the shader keywords
            var keywords = new List<string> { useAlpha ? "_UseAlpha" : "_UseAlpha_OFF" ,
                                              useReflect ?  "_UseReflections" : "_UseReflections_OFF", 
                                              useNormal ? "_UseNormalMap" : "_UseNormalMap_OFF", 
                                              useReflectOverride ? "_ReflectionOverride" : "_ReflectionOverride_OFF",
                                              useRefraction ? "_UseRefraction" : "_UseRefraction_OFF",
                                              //useThickness ? "_HasFakeThickness" : "_HasFakeThicknessOFF"
                                              };
            targetMat.shaderKeywords = keywords.ToArray();
            EditorUtility.SetDirty(targetMat);
        }        
    }

    void Reload(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        Material targetMat = materialEditor.target as Material;
        string[] keyWords = targetMat.shaderKeywords;

        MaterialProperty normalMap = FindProperty("_NormalMap", properties);
        MaterialProperty normalStrength = FindProperty("_NormalStrength", properties);
        bool useNormal = true;
        if(normalMap.textureValue == null)
            useNormal = false;
        else if(normalMap.textureValue.name == "black" || normalStrength.floatValue == 0)
            useNormal = false;

        MaterialProperty reflect = FindProperty("_Reflection", properties);
        MaterialProperty reflectOverride = FindProperty("_ReflectionOverride", properties);
        bool useReflect = true;
        if(reflect.floatValue == 0)
            useReflect = false;
        bool useReflectOverride = false;
        if(reflectOverride.floatValue == 1)
            useReflectOverride = true;

        MaterialProperty _useAlpha = FindProperty("_UseAlpha", properties);
        bool useAlpha = false;
        if(_useAlpha.floatValue == 1)
            useAlpha = true;

        MaterialProperty refraction = FindProperty("_Refraction", properties);
        bool useRefraction = false;
        if(refraction.floatValue != 0)
            useRefraction = true;

        /*MaterialProperty fakeThickness = FindProperty("_FakeThickness", properties);
        bool useThickness = false;
        if(fakeThickness.floatValue != 0)
            useThickness = true;*/

        // if the checkbox is changed, reset the shader keywords
        var keywords = new List<string> { useAlpha ? "_UseAlpha" : "_UseAlpha_OFF" ,
                                            useReflect ?  "_UseReflections" : "_UseReflections_OFF", 
                                            useNormal ? "_UseNormalMap" : "_UseNormalMap_OFF", 
                                            useReflectOverride ? "_ReflectionOverride" : "_ReflectionOverride_OFF",
                                            useRefraction ? "_UseRefraction" : "_UseRefraction_OFF",
                                            //useThickness ? "_HasFakeThickness" : "_HasFakeThicknessOFF"
                                            };
        targetMat.shaderKeywords = keywords.ToArray();
        EditorUtility.SetDirty(targetMat);
    }
}

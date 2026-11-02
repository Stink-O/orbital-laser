import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.util.shaderc.Shaderc;

/**
 * Compiles a GLSL file with shaderc, with the same options Minecraft 26.3's GlslCompiler uses (Vulkan target, automatic
 * uniform binding, no optimisation), and prints the compiler's errors: so a shader can be checked without starting the game.
 *
 *   java ShaderCheck.java FILE.fsh|FILE.vsh
 */
public class ShaderCheck {
	public static void main(String[] args) throws Exception {
		for (String file : args) {
			String source = Files.readString(Path.of(file), StandardCharsets.UTF_8);
			int type = file.endsWith(".vsh") ? 0 : 1;
			ByteBuffer src = MemoryUtil.memUTF8(source, false);
			ByteBuffer name = MemoryUtil.memUTF8(Path.of(file).getFileName().toString());
			ByteBuffer entry = MemoryUtil.memUTF8("main");
			long options = Shaderc.shaderc_compile_options_initialize();
			Shaderc.shaderc_compile_options_set_target_env(options, 0, 4202496);
			Shaderc.shaderc_compile_options_set_auto_bind_uniforms(options, true);
			Shaderc.shaderc_compile_options_set_preserve_bindings(options, false);
			Shaderc.shaderc_compile_options_set_optimization_level(options, 0);
			Shaderc.shaderc_compile_options_add_macro_definition(options, "RENDERPEARL_DEPTH_IS_ZERO_TO_ONE", "");
			long compiler = Shaderc.shaderc_compiler_initialize();
			long result = Shaderc.shaderc_compile_into_spv(compiler, src, type, name, entry, options);
			int status = Shaderc.shaderc_result_get_compilation_status(result);
			if (status == 0) {
				System.out.println("OK    " + file + "  (" + Shaderc.shaderc_result_get_length(result) + " bytes of SPIR-V)");
			} else {
				System.out.println("FAIL  " + file);
				String msg = Shaderc.shaderc_result_get_error_message(result);
				String[] lines = msg.split("\n");
				for (int i = 0; i < Math.min(lines.length, 40); i++) {
					System.out.println("      " + lines[i]);
				}
				if (lines.length > 40) {
					System.out.println("      ... " + (lines.length - 40) + " more lines");
				}
			}
			Shaderc.shaderc_result_release(result);
		}
	}
}

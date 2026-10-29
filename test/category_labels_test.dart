// Same cases as the TV (aliens-syndicate-iplex-web categoryLabels.test.ts).
import 'package:aliens_syndicate_iplex_control/features/home/category_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de-para de categorias', () {
    test('corrige acento e caixa, com a primeira letra maiúscula', () {
      expect(categoryLabel('AÇAO'), 'Ação');
      expect(categoryLabel('ACAO'), 'Ação');
      expect(categoryLabel('comédia'), 'Comédia');
      expect(categoryLabel('FICCAO CIENTIFICA'), 'Ficção científica');
      expect(categoryLabel('DESENHOS'), 'Desenhos');
    });
    test('traduz nomes em inglês e espanhol', () {
      expect(categoryLabel('Action'), 'Ação');
      expect(categoryLabel('Sci-Fi'), 'Ficção científica');
      expect(categoryLabel('Documental'), 'Documentário');
    });
    test('remove prefixos genéricos', () {
      expect(categoryLabel('FILMES | AÇÃO'), 'Ação');
      expect(categoryLabel('Canais - Esportes'), 'Esportes');
    });
    test('padroniza os serviços de streaming', () {
      expect(categoryLabel('HBO MAX'), 'HBO Max');
      expect(categoryLabel('APPLETV+'), 'Apple TV+');
      expect(categoryLabel('PARAMOUNT+'), 'Paramount+');
      expect(categoryLabel('AMAZON PRIME VIDEO'), 'Amazon Prime Video');
    });
    test('todas as variações adultas viram exatamente "Adulto"', () {
      for (final name in [
        'ADULTOS',
        'Adulto +18',
        'XXX',
        '18+',
        'Eróticos',
        'Conteúdo Adulto',
        'adult',
        'PORN',
      ]) {
        expect(categoryLabel(name), 'Adulto');
        expect(isAdultName(name), true);
      }
      expect(isAdultName('Ação'), false);
    });
    test('sem regra: caixa de frase (como "Continuar assistindo"), siglas e marcas preservadas', () {
      expect(categoryLabel('ESPECIAL DE FIM DE ANO'), 'Especial de fim de ano');
      expect(categoryLabel('canais UHD premium'), 'Canais UHD premium');
      expect(categoryLabel('SERIES 24 HORAS'), 'Séries 24 horas');
      expect(categoryLabel('YOUTUBE 24 HORAS'), 'YouTube 24 horas');
      expect(categoryLabel('FICÇÃO/FANTASIA'), 'Ficção e fantasia');
      expect(categoryLabel('  '), 'Sem categoria');
    });
    test('nomes diferentes com o mesmo texto são o mesmo grupo', () {
      expect(categoryKey('AÇAO'), categoryKey('Action'));
      expect(categoryKey('XXX'), categoryKey('Adultos'));
    });
  });
}

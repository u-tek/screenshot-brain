import Foundation
import Testing
@testable import Actions

@Suite struct RecipeStepsTests {
    @Test func numberedLinesAreSteps() {
        let text = """
        Garlic noodles
        2 cups noodles
        1. Boil the noodles.
        2) Fry the garlic.
        Step 3: Toss it all together.
        """
        #expect(RecipeSteps.steps(in: text) == ["Boil the noodles.", "Fry the garlic.", "Toss it all together."])
    }

    @Test func wrappedLinesJoinIntoOneStep() {
        let text = """
        1. Preheat the oven to 200 degrees and
        line a tray with paper.
        2. Roast the pumpkin until
        soft and golden.
        """
        #expect(RecipeSteps.steps(in: text) == [
            "Preheat the oven to 200 degrees and line a tray with paper.",
            "Roast the pumpkin until soft and golden.",
        ])
    }

    @Test func aStepWordOnItsOwnTakesTheNextLine() {
        let text = "Step 1\nChop the onion.\nStep 2\nFry it."
        #expect(RecipeSteps.steps(in: text) == ["Chop the onion.", "Fry it."])
    }

    @Test func ingredientsAreNotSteps() {
        let text = "Ingredients\n2 cups flour\n1.5 tsp salt\n3 eggs"
        #expect(RecipeSteps.steps(in: text).isEmpty)
    }

    @Test func linesUnderAMethodHeadingAreSteps() {
        let text = """
        Ingredients
        2 cups flour
        Method
        Mix the flour and water.
        Knead for ten minutes, then
        rest it.
        Notes
        Keeps for three days.
        """
        #expect(RecipeSteps.steps(in: text) == ["Mix the flour and water.", "Knead for ten minutes, then rest it."])
    }

    @Test func headingsIgnoreCaseAndTakeAColon() {
        #expect(RecipeSteps.steps(in: "DIRECTIONS:\nStir.\nServe.") == ["Stir.", "Serve."])
        #expect(RecipeSteps.steps(in: "Instructions\n- Stir well.\n- Serve hot.") == ["Stir well.", "Serve hot."])
    }

    @Test func aNumberedStepEndsAtTheNextHeading() {
        let text = "1. Bake it.\nNotes\nKeeps well."
        #expect(RecipeSteps.steps(in: text) == ["Bake it."])
    }

    @Test func noStepsFoundIsEmpty() {
        #expect(RecipeSteps.steps(in: "").isEmpty)
        #expect(RecipeSteps.steps(in: "Best pasta ever\nso good").isEmpty)
    }
}
